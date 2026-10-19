module Shoko.Adapter.Http.Request
  ( Endpoint,
    endpoint,
    endpointParts,
    HttpMethod (..),
    HttpPayload (..),
    emptyPayload,
    TraceParent,
    traceParent,
    traceParentBytes,
  )
where

import Control.Exception (SomeException)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS
import Data.Char (isHexDigit)
import Data.Set (Set)
import Data.Text qualified as Text
import Network.HTTP.Client qualified as H
import Shoko.Environment (Capability)
import Shoko.Identifier
import Shoko.Prelude

data HttpMethod = Get | Post | Put | Patch | Delete deriving stock (Eq, Show, Generic)

data Endpoint = Endpoint !Text !H.Request !HttpMethod !Int !(Set Capability) !Bool !(Maybe (BusinessKeyName, ByteString))

-- | Exact host-approved destination. No runtime URL input, redirects, URL
-- credentials, query fragments, or ambient proxy settings are accepted.
endpoint :: Text -> Text -> HttpMethod -> Int -> Set Capability -> Bool -> Maybe (BusinessKeyName, ByteString) -> Either Text Endpoint
endpoint name url method maxBytes extra propagate scope
  | name == "" || maxBytes <= 0 || Text.any (`elem` ['#', '?']) url = Left "invalid-http-endpoint"
  | Just (key, parameter) <- scope, businessKeyNameText key == "" || BS.null parameter = Left "invalid-http-scope"
  | otherwise = case H.parseRequest (Text.unpack url) :: Either SomeException H.Request of
      Left _ -> Left "invalid-http-endpoint"
      Right request
        | not (Text.isPrefixOf "http://" url || Text.isPrefixOf "https://" url) || not (null (H.requestHeaders request)) -> Left "invalid-http-endpoint"
        | otherwise -> Right (Endpoint name request method maxBytes extra propagate scope)

endpointParts :: Endpoint -> (Text, H.Request, HttpMethod, Int, Set Capability, Bool, Maybe (BusinessKeyName, ByteString))
endpointParts (Endpoint name request method limit extra propagate scope) = (name, request, method, limit, extra, propagate, scope)

newtype TraceParent = TraceParent ByteString

traceParent :: ByteString -> Either Text TraceParent
traceParent value = case BS.split '-' value of
  ["00", trace, parent, flags]
    | BS.length trace == 32 && BS.length parent == 16 && BS.length flags == 2,
      all (BS.all (\c -> isHexDigit c && not (c >= 'A' && c <= 'F'))) [trace, parent, flags],
      BS.any (/= '0') trace && BS.any (/= '0') parent ->
        Right (TraceParent value)
  _ -> Left "invalid-traceparent"

traceParentBytes :: TraceParent -> ByteString
traceParentBytes (TraceParent value) = value

-- | Deliberately no Show/JSON instances: values can include secrets.
data HttpPayload = HttpPayload
  { body :: !ByteString,
    contentType :: !ByteString,
    authorization :: !(Maybe ByteString),
    trace :: !(Maybe TraceParent),
    runLabel :: !(Maybe Text)
  }

emptyPayload :: HttpPayload
emptyPayload = HttpPayload "" "application/json" Nothing Nothing Nothing
