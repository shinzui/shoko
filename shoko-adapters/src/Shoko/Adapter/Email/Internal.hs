-- Private provider and run-state boundary. No content-bearing type has a rendering instance.
module Shoko.Adapter.Email.Internal where

import Control.Concurrent.MVar
import Control.Exception (try)
import Control.Monad (foldM)
import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.UUID qualified as UUID
import Data.UUID.V4 (nextRandom)
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (renderQuery, statusCode)
import Shoko.Clock
import Shoko.Environment (Duration)
import Shoko.Identifier

-- Bounds apply independently to every complete sample, including baseline capture.
data EmailLimits = EmailLimits
  { pageSize :: !Int,
    maxPages :: !Int,
    maxDetails :: !Int,
    responseBytes :: !Int,
    scanBytes :: !Int,
    payloadBytes :: !Int,
    requestLimit :: !Duration,
    scanLimit :: !Duration
  }
  deriving stock (Eq, Show)

data Inbox = Inbox !SourceId !Text !BusinessKeyName !Text !Text !EmailLimits
  deriving stock (Eq)

data SendDescriptor = SendDescriptor !Inbox ![Address]
  deriving stock (Eq)

newtype Address = Address Text deriving stock (Eq, Ord)

data Attachment = Attachment
  { attachmentName :: !(Maybe Text),
    attachmentType :: !Text,
    attachmentSize :: !Integer,
    attachmentId :: !Text
  }

data ReceivedEmail = ReceivedEmail
  { receivedId :: !Text,
    emailTo :: ![Address],
    emailFrom :: !Text,
    emailSubject :: !Text,
    emailText :: !(Maybe Text),
    emailHtml :: !(Maybe Text),
    emailHtmlFormat :: !Text,
    emailHeaders :: !(Map Text Text),
    emailAttachments :: ![Attachment]
  }

data EmailPayload = EmailPayload !Address ![Address] !Text !(Maybe Text) !(Maybe Text) !Text

newtype EmailSubmission = EmailSubmission Text

data MessageRef = MessageRef !Text ![Address]

data Page = Page ![MessageRef] !Bool

data Provider = Provider
  { listPage :: Clock -> MonotonicTime -> Maybe Text -> IO (Either Text (Page, Int)),
    getDetail :: Clock -> MonotonicTime -> Text -> IO (Either Text (ReceivedEmail, Int)),
    submit :: Clock -> MonotonicTime -> EmailPayload -> IO (Either Text EmailSubmission)
  }

data ReaderState = ReaderState !(Map Text (Set Text)) !(Map Text Text)

data EmailReader = EmailReader !Inbox !(Maybe SendDescriptor) !Provider !(MVar ReaderState)

freshToken :: IO Text
freshToken = UUID.toText <$> nextRandom

asciiLetter :: Char -> Bool
asciiLetter c = isAsciiLower c || isAsciiUpper c

safeId :: Text -> Bool
safeId t = not (T.null t) && T.length t <= 256 && T.all (\c -> asciiLetter c || isDigit c || c `elem` ['-', '_']) t

-- Deliberately supports bare dot-atom addresses only, preserving local-part case and plus tags.
address :: Text -> Either Text Address
address value = case T.splitOn "@" value of
  [local, domain]
    | T.length value <= 254,
      not (T.null local),
      T.length local <= 64,
      T.all (\c -> asciiLetter c || isDigit c || c `elem` (".!#$%&'*+-/=?^_`{|}~" :: String)) local,
      all (not . T.null) (T.splitOn "." local),
      validDomain domain ->
        Right (Address (local <> "@" <> T.toLower domain))
  _ -> Left "email-invalid-address"

validDomain :: Text -> Bool
validDomain domain = T.length domain <= 253 && T.any (== '.') domain && all valid (T.splitOn "." domain)
  where
    valid label = not (T.null label) && T.length label <= 63 && T.head label /= '-' && T.last label /= '-' && T.all (\c -> asciiLetter c || isDigit c || c == '-') label

addressText :: Address -> Text
addressText (Address t) = t

recipient :: Inbox -> Text -> Either Text Address
recipient (Inbox _ _ _ domain prefix _) token
  | Just parsed <- UUID.fromText token, UUID.toText parsed == token = address (prefix <> token <> "@" <> domain)
  | otherwise = Left "email-invalid-token"

inbox :: SourceId -> Text -> BusinessKeyName -> Text -> Text -> EmailLimits -> Either Text Inbox
inbox label@(SourceId source) account key@(BusinessKeyName semantic) domain prefix limits
  | not (all safeId [source, account, semantic]) = Left "email-invalid-label"
  | not (validDomain domain) || T.length prefix > 28 || not (T.all (\c -> asciiLetter c || isDigit c || c `elem` ['-', '_']) prefix) = Left "email-invalid-recipient-scope"
  | pageSize limits < 1 || pageSize limits > 100 || any (<= 0) [maxPages limits, maxDetails limits, responseBytes limits, scanBytes limits, payloadBytes limits] = Left "email-invalid-limits"
  | scanBytes limits < responseBytes limits || requestLimit limits > scanLimit limits = Left "email-invalid-limits"
  | otherwise = Right (Inbox label account key (T.toLower domain) prefix limits)

sendDescriptor :: Inbox -> [Address] -> Either Text SendDescriptor
sendDescriptor selected senders
  | null senders = Left "email-missing-approved-sender"
  | otherwise = Right (SendDescriptor selected senders)

emailPayload :: Address -> [Address] -> Text -> Maybe Text -> Maybe Text -> Text -> Either Text EmailPayload
emailPayload sender destinations subject plain html key
  | null destinations || length destinations > 50 || T.any (\c -> c < ' ' || c == '\DEL') subject = Left "email-invalid-payload"
  | plain == Nothing && html == Nothing = Left "email-invalid-payload"
  | T.null key || T.length key > 256 || not (T.all (\c -> c >= '!' && c <= '~') key) = Left "email-invalid-idempotency-key"
  | otherwise = Right (EmailPayload sender destinations subject plain html key)

payloadAllowed :: SendDescriptor -> EmailPayload -> Bool
payloadAllowed (SendDescriptor (Inbox _ _ _ domain prefix _) senders) (EmailPayload sender destinations _ _ _ _) =
  sender `elem` senders && all approved destinations
  where
    approved (Address value) = case T.splitOn "@" value of
      [local, actual] | actual == domain, Just token <- T.stripPrefix prefix local -> maybe False (const True) (UUID.fromText token)
      _ -> False

limitsOf :: Inbox -> EmailLimits
limitsOf (Inbox _ _ _ _ _ limits) = limits

-- Complete scans never return partial witnesses. Repeated IDs are deduplicated;
-- conflicting metadata and cursor loops are unavailable evidence.
scan :: Provider -> Inbox -> Clock -> MonotonicTime -> IO (Either Text (Map Text [Address], Int, Int))
scan provider selected clock end = go Nothing Set.empty Map.empty 0 0
  where
    limits = limitsOf selected
    go cursor seen found pages bytes
      | pages >= maxPages limits = pure (Left "email-page-limit")
      | otherwise =
          listPage provider clock end cursor >>= \case
            Left failure -> pure (Left failure)
            Right (Page refs more, size)
              | length refs > pageSize limits || bytes + size > scanBytes limits -> pure (Left "email-scan-limit")
              | more && null refs -> pure (Left "email-empty-page")
              | otherwise -> case foldM insert found refs of
                  Left failure -> pure (Left failure)
                  Right accumulated ->
                    if not more
                      then pure (Right (accumulated, pages + 1, bytes + size))
                      else case reverse refs of
                        MessageRef lastId _ : _ | Set.notMember lastId seen -> go (Just lastId) (Set.insert lastId seen) accumulated (pages + 1) (bytes + size)
                        _ -> pure (Left "email-cursor-loop")
    insert found (MessageRef identity recipients) = case Map.lookup identity found of
      Just previous | previous /= recipients -> Left "email-identity-disagreement"
      _ -> Right (Map.insert identity recipients found)

-- Private loopback seam: production construction below always uses the fixed TLS origin.
newResendReaderAt :: Inbox -> Maybe SendDescriptor -> Text -> H.Request -> IO EmailReader
newResendReaderAt selected sending apiKey origin = do
  manager <-
    H.newManager
      (H.managerSetInsecureProxy H.noProxy (H.managerSetSecureProxy H.noProxy tlsManagerSettings))
        { H.managerRetryableException = const False,
          H.managerIdleConnectionCount = 0
        }
  state <- newMVar (ReaderState Map.empty Map.empty)
  let limits = limitsOf selected
      request clock end method route query body extra = do
        started <- monotonic clock
        let deadline = min end (addDuration started (requestLimit limits))
            remaining = fromInteger (min (toInteger (maxBound :: Int)) (max 1 (differenceMicros deadline started)))
            outgoing =
              origin
                { H.method = method,
                  H.path = route,
                  H.queryString = renderQuery True query,
                  H.requestBody = H.RequestBodyBS body,
                  H.requestHeaders = [("Authorization", T.encodeUtf8 ("Bearer " <> apiKey)), ("Content-Type", "application/json")] ++ extra,
                  H.redirectCount = 0,
                  H.proxy = Nothing,
                  H.responseTimeout = H.responseTimeoutMicro remaining,
                  H.checkResponse = \_ _ -> pure ()
                }
        if started >= deadline
          then pure (Left "email-deadline")
          else do
            result <- bounded clock deadline $ try @H.HttpException $ H.withResponse outgoing manager $ \response ->
              if statusCode (H.responseStatus response) < 200 || statusCode (H.responseStatus response) >= 300
                then pure (Left "email-provider-unavailable")
                else readBounded (responseBytes limits) (H.responseBody response)
            finished <- monotonic clock
            pure $ case result of
              Just (Right answer) | finished <= deadline -> answer
              _ -> Left "email-transport-unavailable"
      parse parser result = do
        bytes <- result
        value <- either (const (Left "email-decode-unavailable")) Right (eitherDecodeStrict' bytes)
        decoded <- either (const (Left "email-decode-unavailable")) Right (parseEither parser value)
        Right (decoded, BS.length bytes)
      provider =
        Provider
          { listPage = \clock end cursor -> parse parsePage <$> request clock end "GET" "/emails/receiving" ([("limit", Just (T.encodeUtf8 (T.pack (show (pageSize limits)))))] ++ maybe [] (\c -> [("after", Just (T.encodeUtf8 c))]) cursor) "" [],
            getDetail = \clock end identity ->
              if not (safeId identity)
                then pure (Left "email-invalid-identity")
                else parse parseEmail <$> request clock end "GET" ("/emails/receiving/" <> T.encodeUtf8 identity) [("html_format", Just "cid")] "" [],
            submit = \clock end payload@(EmailPayload _ _ _ _ _ key) -> do
              let body = BL.toStrict (encode (payloadValue payload))
              if BS.length body > payloadBytes limits
                then pure (Left "email-payload-limit")
                else
                  fmap
                    (fmap (EmailSubmission . fst) . parse (withObject "submission" (\o -> o .: "id" >>= parseIdentity)))
                    (request clock end "POST" "/emails" [] body [("Idempotency-Key", T.encodeUtf8 key)])
          }
  pure (EmailReader selected sending provider state)

readBounded :: Int -> H.BodyReader -> IO (Either Text ByteString)
readBounded limit reader = go 0 []
  where
    go size chunks = do
      chunk <- H.brRead reader
      let total = size + BS.length chunk
      if total > limit
        then pure (Left "email-response-limit")
        else if BS.null chunk then pure (Right (BS.concat (reverse chunks))) else go total (chunk : chunks)

parseIdentity :: Text -> Parser Text
parseIdentity identity = if safeId identity then pure identity else fail "invalid identity"

parseAddress :: Text -> Parser Address
parseAddress = either (const (fail "invalid address")) pure . address

parseRecipients :: [Text] -> Parser [Address]
parseRecipients values = if null values then fail "missing direct recipients" else traverse parseAddress values

parsePage :: Value -> Parser Page
parsePage = withObject "page" $ \o -> Page <$> (o .: "data" >>= traverse (withObject "reference" $ \r -> MessageRef <$> (r .: "id" >>= parseIdentity) <*> (r .: "to" >>= parseRecipients))) <*> o .: "has_more"

parseEmail :: Value -> Parser ReceivedEmail
parseEmail = withObject "received email" $ \o ->
  ReceivedEmail
    <$> (o .: "id" >>= parseIdentity)
    <*> (o .: "to" >>= parseRecipients)
    <*> o .: "from"
    <*> o .: "subject"
    <*> o .: "text"
    <*> o .: "html"
    <*> (o .: "html_format" >>= \v -> if v `elem` ["cid", "data_uri"] then pure v else fail "invalid format")
    <*> o .: "headers"
    <*> (o .: "attachments" >>= traverse parseAttachment)
  where
    parseAttachment = withObject "attachment" $ \a ->
      Attachment
        <$> a .: "filename"
        <*> a .: "content_type"
        <*> (a .: "size" >>= \n -> if n >= 0 then pure n else fail "invalid size")
        <*> a .: "id"

payloadValue :: EmailPayload -> Value
payloadValue (EmailPayload sender destinations subject plain html _) =
  object $
    ["from" .= addressText sender, "to" .= map addressText destinations, "subject" .= subject]
      ++ maybe [] (\v -> ["text" .= v]) plain
      ++ maybe [] (\v -> ["html" .= v]) html
