{-# LANGUAGE GADTs #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RankNTypes #-}

module Email.Sending (tests) where

import Control.Monad (void)
import Data.Aeson
import Data.IORef
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Email.Contract hiding (tests)
import EmailSmoke.Scenario
import Network.HTTP.Client qualified as H
import Shoko
import Shoko.Adapter.Email qualified as E
import Shoko.Adapter.Email.Internal qualified as I
import Shoko.Adapter.Email.Resend qualified as Resend
import Shoko.Clock
import Shoko.Result hiding (binding)
import System.Environment (getEnv)
import Test.Tasty
import "shoko-adapters" Shoko.Adapter.Http qualified as Http

sender :: IO E.Address
sender = right (E.address "approved@sender.invalid")

sendSetup :: E.Inbox -> Text -> IO (E.SendDescriptor, E.Address, IO E.EmailReader)
sendSetup selected account = do
  from <- sender
  send <- right (E.sendDescriptor selected [from])
  origin <- getEnv "SHOKO_TEST_EMAIL" >>= H.parseRequest
  pure (send, from, I.newResendReaderAt selected (Just send) account origin)

runSmoke :: E.Inbox -> Text -> IO RunResult
runSmoke selected account = do
  (send, from, acquire) <- sendSetup selected account
  resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options (smokeBinding selected (Just (send, from)) acquire) (smokeScenario True))
  runScenario realClock (LogicalInput "email-smoke-fixture" []) resolved

metric :: Text -> Key -> Int -> IO ()
metric account field value =
  fixture account "/control/" Nothing >>= \case
    Object values -> check (lookupNumber field values == Just value)
    _ -> fail "missing fixture metrics"

tests :: TestTree
tests =
  testGroup
    "controlled sending and independent receipt"
    [ test "the executable's shared scenario sends then observes receipt" $ do
        (selected, account, _) <- newCase
        runSmoke selected account >>= expectVerdict Pass
        metric account "sends" 1,
      test "accepted send without arrival cannot pass receipt" $ do
        (selected, account, _) <- newCase
        void (fixture account "/control/" (Just (object ["deliver" .= False])))
        runSmoke selected account >>= expectVerdict Fail
        metric account "sends" 1,
      test "timeout after server acceptance is Unknown and is never retried" $ do
        (selected, account, _) <- newCase
        void (fixture account "/control/" (Just (object ["fault" .= ("send-slow" :: Text)])))
        runSmoke selected account >>= expectVerdict Unknown
        metric account "sends" 1,
      test "undecodable acceptance remains Unknown" $ do
        (selected, account, _) <- newCase
        void (fixture account "/control/" (Just (object ["fault" .= ("send-invalid" :: Text)])))
        runSmoke selected account >>= expectVerdict Unknown
        metric account "sends" 1,
      test "explicit stable keys deduplicate identical requests and separate actions" $ do
        (selected, account, token) <- newCase
        (_, from, acquire) <- sendSetup selected account
        I.EmailReader _ _ provider _ <- acquire
        destination <- right (E.recipient selected token)
        let payload subject keyValue = right (E.emailPayload from [destination] subject (Just "private") Nothing keyValue)
            submit value = do
              now <- monotonic realClock
              I.submit provider realClock (addDuration now (ms 1000)) value
        original <- payload "same" (token <> ":action-a")
        first <- submit original
        again <- submit original
        different <- payload "same" (token <> ":action-b") >>= submit
        conflict <- payload "changed" (token <> ":action-a") >>= submit
        check
          ( case (first, again, different, conflict) of
              (Right (I.EmailSubmission a), Right (I.EmailSubmission b), Right (I.EmailSubmission c), Left _) -> a == b && a /= c
              _ -> False
          )
        metric account "sends" 4,
      test "denied send permissions and missing consent acquire nothing" $ do
        (selected, account, _) <- newCase
        (send, from, _) <- sendSetup selected account
        acquisitions <- newIORef (0 :: Int)
        let selectedBinding = smokeBinding selected (Just (send, from)) (modifyIORef' acquisitions (+ 1) >> fail "must not acquire")
            denied = Environment "denied" False (Set.fromList [ReadState, WriteState, SendHttp, SyntheticResource]) defaultPolicy
        check (either (const True) (const False) (resolveScenario denied options selectedBinding (smokeScenario True)))
        check (either (const True) (const False) (resolveScenario fixtureEnvironment (RunOptions "no-consent" False "fixture" Nothing Nothing) selectedBinding (smokeScenario True)))
        readIORef acquisitions >>= check . (== 0)
        metric account "sends" 0,
      test "forbidden sender/destination and mismatched descriptors send no requests" $ do
        (selected, account, token) <- newCase
        (send, from, acquire) <- sendSetup selected account
        destination <- right (E.recipient selected token)
        forbidden <- right (E.address "person@unapproved.invalid")
        wrongSender <- right (E.address "other@sender.invalid")
        let attempt descriptor actual payload = do
              let handlers :: OperationRole -> SmokeOp a -> Either HandlerBuildError (Maybe (Handler E.EmailReader a))
                  handlers ActionOperation (SendInput _) = Just <$> E.emailActionHandler descriptor (const (pure (Right payload)))
                  handlers role operation = bindingHandler (smokeBinding selected (Just (send, from)) actual) role operation
                  selectedBinding = binding "send-control" (const actual) (const (pure Retained)) handlers
                  source = smokeScenario True
              resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options selectedBinding source)
              runScenario realClock (LogicalInput "send-control" []) resolved >>= expectVerdict Unknown
        wrongDestination <- right (E.emailPayload from [forbidden] "subject" (Just "private") Nothing (token <> ":forbidden"))
        attempt send acquire wrongDestination
        badSender <- right (E.emailPayload wrongSender [destination] "subject" (Just "private") Nothing (token <> ":sender"))
        attempt send acquire badSender
        mismatched <- right (E.sendDescriptor selected [wrongSender])
        valid <- right (E.emailPayload from [destination] "subject" (Just "private") Nothing (token <> ":mismatch"))
        attempt mismatched acquire valid
        metric account "sends" 0,
      test "payload bounds reject before POST and invalid private values never construct" $ do
        (_, account, token) <- newCase
        selected <- box limits {E.payloadBytes = 32}
        runSmoke selected account >>= expectVerdict Unknown
        metric account "sends" 0
        from <- sender
        destination <- right (E.recipient selected token)
        check (either (const True) (const False) (E.emailPayload from [destination] "subject" (Just "private") Nothing "bad\r\nkey"))
        check (either (const True) (const False) (E.emailPayload from [destination] "bad\nsubject" (Just "private") Nothing "valid"))
        check (either (const True) (const False) (E.address "bad\r\n@sender.invalid"))
        check (either (const True) (const False) (Resend.resendCredentials "bad\nkey"))
        preserved <- right (E.address "Case+tag@DOMAIN.invalid")
        check (E.addressText preserved == "Case+tag@domain.invalid"),
      test "inbound ticket workflow uses email as an action input" ticketWorkflow
    ]

data TicketOp a where
  AllocateTicket :: TicketOp Text
  SendTicket :: Input Text -> TicketOp E.EmailSubmission
  TicketState :: Input Text -> TicketOp Bool

instance Vocabulary TicketOp where
  describeOperation AllocateTicket = OperationInfo "ticket-token" Set.empty [] []
  describeOperation (SendTicket token) = OperationInfo "submit-ticket-by-email" Set.empty (inputDependencies token) []
  describeOperation (TicketState token) = OperationInfo "ticket-created" Set.empty (inputDependencies token) []

ticketWorkflow :: IO ()
ticketWorkflow = do
  (selected, account, _) <- newCase
  (send, from, acquire) <- sendSetup selected account
  base <- T.pack <$> getEnv "SHOKO_TEST_EMAIL"
  endpoint <- right (Http.endpoint "ticket" (base <> "/ticket") Http.Get 1024 Set.empty False (Just (key, "id")))
  config <- right (Http.httpConfig [endpoint])
  let handlers :: forall a. OperationRole -> TicketOp a -> Either HandlerBuildError (Maybe (Handler (E.EmailReader, Http.Http) a))
      handlers FixtureOperation AllocateTicket = Right (Just (actionHandler (requiring [SyntheticResource] noRequirements) (\_ _ -> ActionObserved "allocated" <$> E.freshToken)))
      handlers ActionOperation (SendTicket input) =
        Just . focus fst
          <$> E.emailActionHandler
            send
            ( \context -> do
                value <- resolveInput context input
                pure $ do
                  token <- either (const (Left "input-unavailable")) Right value
                  destination <- E.recipient selected token
                  E.emailPayload from [destination] "Ticket" (Just "controlled ticket") Nothing (token <> ":ticket")
            )
      handlers ObservationOperation (TicketState _) = Just . focus snd <$> Http.httpObservationHandler config "ticket" (const (pure (Right Http.emptyPayload))) (\status bytes -> if status == 200 && bytes `elem` ["true", "false"] then Right (bytes == "true") else Left Http.ResponseUndecodable)
      handlers _ _ = Right Nothing
      selectedBinding = binding "inbound-ticket" (const ((,) <$> acquire <*> Http.newHttp config)) (const (pure Retained)) handlers
      source = scenario "inbound-ticket" "Email creates a ticket" "1" $ do
        token <- given "mailbox" (accept ["allocated"] AllocateTicket)
        void (act "submit" (accept ["accepted"] (SendTicket (fromRef token))))
        correlationHandle <- correlate (CorrelationAlias "ticket") key (fromRef token)
        expect $ eventually "created" (correlatedBy correlationHandle (observe "ticket-present" (TicketState (fromRef token)) id))
  resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options selectedBinding source)
  runScenario realClock (LogicalInput "inbound-ticket" []) resolved >>= expectVerdict Pass
  metric account "sends" 1
