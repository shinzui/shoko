module Shoko.Adapter.Email.Resend (ResendCredentials, resendCredentials, newResendReader) where

import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Client qualified as H
import Shoko.Adapter.Email.Internal

newtype ResendCredentials = ResendCredentials Text

resendCredentials :: Text -> Either Text ResendCredentials
resendCredentials key
  | T.null key || not (T.all (\c -> c >= '!' && c <= '~') key) = Left "email-invalid-credentials"
  | otherwise = Right (ResendCredentials key)

-- Pure construction and inspection never call this acquisition function.
newResendReader :: Inbox -> Maybe SendDescriptor -> ResendCredentials -> IO EmailReader
newResendReader selected sending (ResendCredentials key) = do
  origin <- H.parseRequest "https://api.resend.com"
  newResendReaderAt selected sending key origin
