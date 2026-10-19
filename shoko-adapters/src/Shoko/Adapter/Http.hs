module Shoko.Adapter.Http
  ( HttpConfig,
    httpConfig,
    Http,
    newHttp,
    HttpPayloadError (..),
    httpActionHandler,
    httpObservationHandler,
    httpAction,
    httpObservation,
    module Shoko.Adapter.Http.Request,
    HttpFailure (..),
  )
where

import Control.Exception (try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (renderQuery, statusCode)
import Shoko.Action
import Shoko.Adapter.Http.Evidence
import Shoko.Adapter.Http.Request
import Shoko.Binding
import Shoko.Clock
import Shoko.Correlation
import Shoko.Environment
import Shoko.Identifier
import Shoko.Observation
import Shoko.Prelude

newtype HttpConfig = HttpConfig (Map Text Endpoint)

data Http = Http !HttpConfig !H.Manager

httpConfig :: [Endpoint] -> Either Text HttpConfig
httpConfig endpoints =
  let entries = [(name, item) | item <- endpoints, let (name, _, _, _, _, _, _) = endpointParts item]
   in if Map.size (Map.fromList entries) == length entries then Right (HttpConfig (Map.fromList entries)) else Left "duplicate-http-endpoint"

-- | The library owns Manager lifetime. With zero idle connections every
-- response scope closes its socket. TLS certificate verification stays on.
newHttp :: HttpConfig -> IO Http
newHttp config =
  Http config
    <$> H.newManager
      (H.managerSetInsecureProxy H.noProxy (H.managerSetSecureProxy H.noProxy tlsManagerSettings))
        { H.managerRetryableException = const False,
          H.managerIdleConnectionCount = 0
        }

data HttpPayloadError = PayloadInputError !InputResolutionError | InvalidPayload
  deriving stock (Eq, Show, Generic)

lookupEndpoint :: HttpConfig -> Text -> Either HandlerBuildError Endpoint
lookupEndpoint (HttpConfig endpoints) key = maybe (Left (EndpointNotAllowlisted key)) Right (Map.lookup key endpoints)

endpointContract :: Endpoint -> BindingContract
endpointContract selected =
  let (_, _, method, _, extra, _, _) = endpointParts selected
   in requiring (SendHttp : (if method == Get then ReadState else WriteState) : Set.toList extra) noRequirements

-- Compare all executable descriptor fields before any network IO.
sameEndpoint :: Endpoint -> Endpoint -> Bool
sameEndpoint left right =
  let (ln, lr, lm, ll, lc, lp, ls) = endpointParts left
      (rn, rr, rm, rl, rc, rp, rs) = endpointParts right
      target r = (H.secure r, H.host r, H.port r, H.path r)
   in (ln, target lr, lm, ll, lc, lp, ls) == (rn, target rr, rm, rl, rc, rp, rs)

configuredEndpoint :: Endpoint -> Http -> Bool
configuredEndpoint descriptor (Http (HttpConfig endpoints) _) =
  let (key, _, _, _, _, _, _) = endpointParts descriptor
   in maybe False (sameEndpoint descriptor) (Map.lookup key endpoints)

-- Reuse the manager, but execute exactly the descriptor whose contract was checked.
declaredEndpoint :: Endpoint -> Http -> Http
declaredEndpoint descriptor (Http _ manager) =
  let (key, _, _, _, _, _, _) = endpointParts descriptor
   in Http (HttpConfig (Map.singleton key descriptor)) manager

httpActionHandler :: HttpConfig -> Text -> (CallContext -> IO (Either HttpPayloadError HttpPayload)) -> (Int -> ByteString -> Either HttpFailure (Text, a)) -> Either HandlerBuildError (Handler Http a)
httpActionHandler config key build decode = do
  descriptor <- lookupEndpoint config key
  pure $ actionHandler (endpointContract descriptor) $ \resource context ->
    if not (configuredEndpoint descriptor resource)
      then pure (ActionUnavailable "endpoint-descriptor-mismatch")
      else
        build context >>= \case
          Left _ -> pure (ActionUnavailable "payload-unavailable")
          Right payload -> case propagatedPayload context payload of
            Left _ -> pure (ActionUnavailable "payload-unavailable")
            Right prepared -> httpAction (declaredEndpoint descriptor resource) context key prepared decode

httpObservationHandler :: HttpConfig -> Text -> (CallContext -> IO (Either HttpPayloadError HttpPayload)) -> (Int -> ByteString -> Either HttpFailure a) -> Either HandlerBuildError (Handler Http a)
httpObservationHandler config key build decode = do
  descriptor <- lookupEndpoint config key
  let (_, _, method, _, _, _, scope) = endpointParts descriptor
  if method /= Get then Left (ObservationMethodNotGet key) else pure ()
  keyName <- maybe (Left (ObservationScopeMissing key)) (Right . fst) scope
  pure $ observationHandler (endpointContract descriptor) (RequiresBusinessKey keyName) (sampledSource (SourceId key)) $ \resource context ->
    if not (configuredEndpoint descriptor resource)
      then pure (ObservationUnavailable "endpoint-descriptor-mismatch")
      else
        build context >>= \case
          Left _ -> pure (ObservationUnavailable "payload-unavailable")
          Right payload -> case propagatedPayload context payload of
            Left _ -> pure (ObservationUnavailable "payload-unavailable")
            Right prepared -> httpObservation (declaredEndpoint descriptor resource) context key prepared decode

-- A declaration supplies the run ID independently of this observation's selection.
-- Endpoint opt-in still controls whether the request transmits it.
propagatedPayload :: CallContext -> HttpPayload -> Either HttpPayloadError HttpPayload
propagatedPayload context payload@(HttpPayload body contentType authorization trace label) = case (executionId context, label) of
  (Just expected, Just actual) | expected /= actual -> Left InvalidPayload
  (Just expected, _) -> Right (HttpPayload body contentType authorization trace (Just expected))
  _ -> Right payload

methodBytes :: HttpMethod -> ByteString
methodBytes Get = "GET"
methodBytes Post = "POST"
methodBytes Put = "PUT"
methodBytes Patch = "PATCH"
methodBytes Delete = "DELETE"

request :: Http -> CallContext -> Bool -> Text -> HttpPayload -> IO (Either HttpFailure (Int, ByteString, MonotonicTime, MonotonicTime, [(Text, PublicValue)]))
request (Http (HttpConfig endpoints) manager) context isRead key (HttpPayload body contentType authorization trace runLabel)
  | any (BS.any (`elem` [10, 13])) (contentType : maybe [] pure authorization)
      || maybe False (\label -> Text.null label || Text.length label > 256 || Text.any (\c -> c < ' ' || c > '~') label) runLabel =
      pure (Left InvalidHttpInput)
  | otherwise =
      case Map.lookup key endpoints of
        Nothing -> pure (Left EndpointNotAllowed)
        Just endpointValue -> do
          let (_, template, method, limit, _, propagate, scope) = endpointParts endpointValue
              scopedQuery =
                if isRead
                  then case (method, scope, selected) of
                    (Get, Just (keyName, parameter), Just (ByBusinessKey selectedKey value))
                      | keyName == selectedKey && value /= "" -> Right (renderQuery True [(parameter, Just (Text.encodeUtf8 value))])
                    _ -> Left HttpCorrelationUnavailable
                  else Right ""
          case scopedQuery of
            Left failure -> pure (Left failure)
            Right query -> do
              started <- now
              if started >= end
                then pure (Left HttpDeadlineExpired)
                else do
                  let remaining = fromInteger (min (toInteger (maxBound :: Int)) (differenceMicros end started))
                      executionHeader = case runLabel of
                        Just runId | propagate -> [("x-shoko-execution-id", Text.encodeUtf8 runId)]
                        _ -> []
                      headers =
                        [("Content-Type", contentType)]
                          ++ maybe [] (\value -> [("Authorization", value)]) authorization
                          ++ maybe [] (\value -> [("traceparent", traceParentBytes value)]) trace
                          ++ executionHeader
                      outgoing =
                        template
                          { H.method = methodBytes method,
                            H.requestBody = H.RequestBodyBS body,
                            H.requestHeaders = headers,
                            H.queryString = query,
                            H.redirectCount = 0,
                            H.proxy = Nothing,
                            H.responseTimeout = H.responseTimeoutMicro (max 1 remaining),
                            H.checkResponse = \_ _ -> pure ()
                          }
                  response <- bound end $ try @H.HttpException $ H.withResponse outgoing manager $ \incoming -> do
                    bytes <- readBounded limit (H.responseBody incoming)
                    pure ((,) (statusCode (H.responseStatus incoming)) <$> bytes)
                  finished <- now
                  pure $ case response of
                    Nothing -> Left HttpDeadlineExpired
                    Just (Left _) -> Left TransportUnavailable
                    Just (Right (Left failure)) -> Left failure
                    Just (Right (Right (status, bytes))) ->
                      Right
                        ( status,
                          bytes,
                          started,
                          finished,
                          [("endpoint", PublicChoice key), ("method", PublicChoice (Text.decodeUtf8 (methodBytes method))), ("status", PublicCount (toInteger status))]
                        )
  where
    end = requestDeadline context
    selected = correlation context
    Clock now _ _ bound = callClock context

readBounded :: Int -> H.BodyReader -> IO (Either HttpFailure ByteString)
readBounded limit reader = go 0 []
  where
    go size chunks = do
      chunk <- H.brRead reader
      let total = size + BS.length chunk
      if BS.null chunk
        then pure (Right (BS.concat (reverse chunks)))
        else
          if total > limit
            then pure (Left ResponseTooLarge)
            else go total (chunk : chunks)

-- | The decoder explicitly classifies status and body into domain tags. No
-- generic status code, exception, or timeout is an expected rejection.
httpAction :: Http -> CallContext -> Text -> HttpPayload -> (Int -> ByteString -> Either HttpFailure (Text, a)) -> IO (ActionOutcome a)
httpAction resource context key payload decode =
  request resource context False key payload >>= \case
    Left failure -> pure (ActionUnavailable (failureCode failure))
    Right (status, bytes, _, _, details) -> case decode status bytes of
      Left failure -> pure (ActionUnavailable (failureCode failure))
      Right (tag, value) -> pure (ActionObservedWithDetails tag value details)

-- | GET reads always inject the selected business key through the endpoint's
-- declared query parameter; they cannot fall back to an uncorrelated read.
httpObservation :: Http -> CallContext -> Text -> HttpPayload -> (Int -> ByteString -> Either HttpFailure a) -> IO (ObservationOutcome a)
httpObservation resource context key payload decode =
  request resource context True key payload >>= \case
    Left failure -> pure (ObservationUnavailable (failureCode failure))
    Right (status, bytes, started, finished, details) -> case decode status bytes of
      Left failure -> pure (ObservationUnavailable (failureCode failure))
      Right value -> pure (ObservedWithDetails [Occurrence Nothing value] (Coverage SampledState started finished True) details)
