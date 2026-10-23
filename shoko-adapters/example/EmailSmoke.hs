module Main (main) where

import Control.Exception (IOException, try)
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import EmailSmoke.Config qualified as Config
import EmailSmoke.Scenario
import Shoko
import Shoko.Adapter.Email qualified as E
import Shoko.Adapter.Email.Resend qualified as Resend
import Shoko.Clock (realClock)
import Shoko.Result
import Shoko.Result.Json (encodeRunResult)
import System.Environment (getArgs)
import System.Exit (exitFailure)

-- Flags choose a fixed scenario/policy. Operational sources cannot grant permissions.
data Options = Options !Bool !Bool !Bool !(Maybe FilePath)

parse :: [String] -> Either Text Options
parse = go (Options False False False Nothing)
  where
    go options [] = Right options
    go (Options _ consent receive config) ("--inspect" : rest) = go (Options True consent receive config) rest
    go (Options inspect _ receive config) ("--allow-synthetic" : rest) = go (Options inspect True receive config) rest
    go (Options inspect consent _ config) ("--receive-only" : rest) = go (Options inspect consent True config) rest
    go (Options inspect consent receive Nothing) ("--config" : path : rest) = go (Options inspect consent receive (Just path)) rest
    go _ _ = Left "email-arguments-invalid"

main :: IO ()
main = do
  args <- getArgs
  case parse args of
    Left failure -> stop failure
    Right options -> do
      result <- try @IOException (execute options)
      case result of
        Left _ -> stop "email-host-unavailable"
        Right () -> pure ()

stop :: Text -> IO a
stop failure = putStrLn (T.unpack failure) >> exitFailure

execute :: Options -> IO ()
execute (Options inspect consent receive path) = do
  (config, _) <- Config.loadConfig path >>= either stop pure
  let sending = not receive
      source = smokeScenario sending
      environment = Environment "approved-email-test" False (Set.fromList [ReadState, WriteState, SendHttp, ExternalSideEffect, SyntheticResource]) (Config.policy config)
      options = RunOptions "email-smoke-inspection" (consent || inspect) "shoko-email-smoke" Nothing Nothing
  placeholder <- either stop pure (E.address "approved@approved.invalid")
  (previewInbox, previewSend) <- either stop pure (Config.descriptors config "approved.invalid" (if sending then Just placeholder else Nothing))
  -- Preflight uses safe placeholders and an acquisition action that is never run.
  case resolveScenario environment options (smokeBinding previewInbox previewSend (fail "inspection acquisition")) source of
    Left _ -> stop "email-policy-denied"
    Right _ | inspect -> putStrLn "email-inspection-valid (sampled receipt; approved test scope; no acquisition)"
    Right _ -> do
      Config.PrivateValues credential domain sender <- Config.resolvePrivate sending config >>= either stop pure
      (selected, send) <- either (const (stop "email-private-inputs-unavailable")) pure (Config.descriptors config domain sender)
      token <- E.freshToken
      let liveOptions = RunOptions token consent "shoko-email-smoke" Nothing Nothing
          acquired = Resend.newResendReader selected (fst <$> send) credential
      resolved <- either (const (stop "email-policy-denied")) pure (resolveScenario environment liveOptions (smokeBinding selected send acquired) source)
      result <- runScenario realClock (LogicalInput "email-input-receipt-v1" []) resolved
      BL.putStrLn (encodeRunResult result)
      case result of
        Verification VerificationResult {verdict = Pass} -> pure ()
        _ -> exitFailure
