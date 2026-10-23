{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}

-- A context-owned consumer shared by the executable and its loopback contract test.
module EmailSmoke.Scenario (SmokeOp (..), smokeScenario, smokeBinding, mailboxKey) where

import Control.Monad (void)
import Data.Set qualified as Set
import Data.Text (Text)
import Shoko
import Shoko.Adapter.Email qualified as E

mailboxKey :: BusinessKeyName
mailboxKey = BusinessKeyName "testMailboxId"

data SmokeOp a where
  NewMailbox :: SmokeOp Text
  SendInput :: Input Text -> SmokeOp E.EmailSubmission
  Receipt :: Input Text -> SmokeOp Bool

instance Vocabulary SmokeOp where
  describeOperation NewMailbox = OperationInfo "new-test-mailbox-token" Set.empty [] []
  describeOperation (SendInput token) = OperationInfo "send-email-input" Set.empty (inputDependencies token) []
  describeOperation (Receipt token) = OperationInfo "received-input-email" Set.empty (inputDependencies token) []

smokeScenario :: Bool -> Scenario SmokeOp
smokeScenario sending = scenario "email-input-receipt" "Send a controlled input and observe receipt" "1" $ do
  token <- given "mailbox" (accept ["allocated"] NewMailbox)
  if sending then void (act "send-input" (accept ["accepted"] (SendInput (fromRef token)))) else pure ()
  correlationHandle <- correlate (CorrelationAlias "mailbox") mailboxKey (fromRef token)
  expect $ eventually "received" (correlatedBy correlationHandle (observe "expected-input" (Receipt (fromRef token)) id))

smokeBinding :: E.Inbox -> Maybe (E.SendDescriptor, E.Address) -> IO E.EmailReader -> Binding SmokeOp E.EmailReader
smokeBinding descriptor sending acquire = binding "resend-email-smoke" (const acquire) (const (pure Retained)) handlers
  where
    handlers :: forall a. OperationRole -> SmokeOp a -> Either HandlerBuildError (Maybe (Handler E.EmailReader a))
    handlers FixtureOperation NewMailbox = Right (Just (actionHandler (requiring [SyntheticResource] noRequirements) (\_ _ -> ActionObserved "allocated" <$> E.freshToken)))
    handlers ActionOperation (SendInput token) = case sending of
      Nothing -> Right Nothing
      Just (send, sender) ->
        Just
          <$> E.emailActionHandler
            send
            ( \context -> do
                input <- resolveInput context token
                pure $ do
                  value <- either (const (Left "email-input-unavailable")) Right input
                  destination <- E.recipient descriptor value
                  E.emailPayload sender [destination] "Shoko controlled input" (Just "Shoko controlled input") Nothing (value <> ":send-input")
            )
    handlers ObservationOperation (Receipt token) = Just <$> E.emailObservationHandler descriptor token (\email -> Right (E.emailSubject email == "Shoko controlled input"))
    handlers _ _ = Right Nothing
