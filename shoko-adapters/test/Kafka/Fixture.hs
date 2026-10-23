module Kafka.Fixture where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (wait, withAsync)
import Control.Concurrent.MVar
import Control.Exception (bracket, finally)
import Control.Monad (unless, void)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID
import GHC.Stack (HasCallStack, callStack, prettyCallStack)
import Hedgehog (evalIO, property, withTests)
import Kafka.Consumer qualified as C
import Kafka.Producer qualified as P
import Kafka.Transaction qualified as T
import Network.Socket qualified as N
import Network.Socket.ByteString qualified as NB
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.Process
import System.Timeout (timeout)
import Test.Tasty (TestTree)
import Test.Tasty.Hedgehog (testPropertyNamed)

data Broker = Broker {bootstrap :: !Text, logDirectory :: !FilePath}

check :: (HasCallStack) => Bool -> IO ()
check value = unless value (fail ("Kafka broker contract assertion failed\n" <> prettyCallStack callStack))

right :: Either e a -> IO a
right = either (const (fail "Kafka fixture operation failed")) pure

test :: String -> IO () -> TestTree
test title action = testPropertyNamed title (fromString title) (withTests 1 (property (evalIO bounded)))
  where
    bounded = timeout 60000000 action >>= maybe (fail "Kafka broker test deadline") pure

unique :: IO Text
unique = UUID.toText <$> UUID.nextRandom

tool :: Broker -> String -> [String] -> String -> IO String
tool (Broker bootstrap logs) executable arguments input = do
  inherited <- getEnvironment
  let command = (proc executable (["--bootstrap-server", Text.unpack bootstrap] ++ arguments)) {env = Just (("LOG_DIR", logs) : filter ((/= "LOG_DIR") . fst) inherited)}
  (status, output, _) <- readCreateProcessWithExitCode command input
  check (status == ExitSuccess)
  pure output

newTopic :: Broker -> Int -> IO C.TopicName
newTopic broker partitions = do
  topic <- ("fixture-" <>) <$> unique
  _ <- tool broker "kafka-topics.sh" ["--create", "--topic", Text.unpack topic, "--partitions", show partitions, "--replication-factor", "1"] ""
  pure (C.TopicName topic)

-- These properties exercise the released client independently of the adapter.
observerProperties :: Text -> IO C.ConsumerProperties
observerProperties bootstrap = do
  identity <- ("shoko-observer-" <>) <$> unique
  pure $
    C.brokersList [C.BrokerAddress bootstrap]
      <> C.groupId (C.ConsumerGroupId identity)
      <> C.noAutoCommit
      <> C.noAutoOffsetStore
      <> C.extraProp "enable.partition.eof" "true"
      <> C.extraProp "allow.auto.create.topics" "false"
      <> C.extraProp "isolation.level" "read_committed"
      <> C.callbackPollMode C.CallbackPollModeSync
      <> C.setCallback (C.errorCallback (\_ _ -> pure ()))
      <> C.setCallback (C.logCallback (\_ _ _ -> pure ()))

withObserver :: Broker -> (C.KafkaConsumer -> IO a) -> IO a
withObserver (Broker bootstrap _) = bracket (observerProperties bootstrap >>= C.newAssignedConsumer >>= right) C.destroyConsumer

withProducer :: Broker -> Maybe Text -> (P.KafkaProducer -> IO a) -> IO a
withProducer (Broker bootstrap _) transaction body =
  bracket (P.newProducer properties >>= right) P.closeProducer $ \producer -> do
    case transaction of
      Nothing -> pure ()
      Just _ -> T.initTransactions producer (C.Timeout 10000) >>= check . (== Nothing)
    body producer
  where
    properties =
      P.brokersList [C.BrokerAddress bootstrap]
        <> P.extraProps (Map.fromList ([("message.timeout.ms", "10000")] ++ maybe [] (\name -> [("transactional.id", name)]) transaction))
        <> P.setCallback (P.errorCallback (\_ _ -> pure ()))
        <> P.setCallback (P.logCallback (\_ _ _ -> pure ()))

produce :: P.KafkaProducer -> C.TopicName -> Int -> Maybe BS.ByteString -> [(BS.ByteString, BS.ByteString)] -> Maybe BS.ByteString -> IO ()
produce producer topic partition key headers value = do
  P.produceMessage producer (P.ProducerRecord topic (P.SpecifiedPartition partition) key value (C.headersFromList headers)) >>= check . (== Nothing)
  P.flushProducer producer

begin :: P.KafkaProducer -> IO ()
begin producer = T.beginTransaction producer >>= check . (== Nothing)

commit :: P.KafkaProducer -> IO ()
commit producer = T.commitTransaction producer (C.Timeout 10000) >>= check . null

abort :: P.KafkaProducer -> IO ()
abort producer = T.abortTransaction producer (C.Timeout 10000) >>= check . null

-- Every accepted connection is drained until EOF. All threads and sockets are
-- scoped to this fixture, including on a failing assertion.
withSilentBroker :: (Text -> IO () -> IO () -> IO a) -> IO a
withSilentBroker body = bracket open N.close $ \listener -> do
  port <- N.socketPort listener
  accepted <- newEmptyMVar
  closed <- newEmptyMVar
  let serve = bracket (fst <$> N.accept listener) N.close $ \connection -> do
        putMVar accepted ()
        let drain = NB.recv connection 4096 >>= \bytes -> unless (BS.null bytes) drain
        drain `finally` putMVar closed ()
      await variable = timeout 1000000 (readMVar variable) >>= check . (== Just ())
  withAsync serve $ \server -> do
    result <- body ("127.0.0.1:" <> Text.pack (show port)) (await accepted) (await closed)
    void (wait server)
    pure result
  where
    open = do
      socket <- N.socket N.AF_INET N.Stream N.defaultProtocol
      N.setSocketOption socket N.ReuseAddr 1
      N.bind socket (N.SockAddrInet 0 (N.tupleToHostAddress (127, 0, 0, 1)))
      N.listen socket 16
      pure socket

-- Avoid tight empty-poll loops in eventual fixture assertions.
pause :: IO ()
pause = threadDelay 10000
