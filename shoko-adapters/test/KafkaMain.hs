module Main (main) where

import Data.Text qualified as Text
import Kafka.Contract (tests)
import Kafka.Fixture (Broker (..))
import Kafka.Spike qualified as Spike
import System.Environment (getEnv)
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = do
  contracts <- tests
  broker <- Broker . Text.pack <$> getEnv "SHOKO_KAFKA_BOOTSTRAP" <*> getEnv "SHOKO_KAFKA_LOG_DIR"
  defaultMain (testGroup "Kafka adapter" [Spike.tests broker, contracts])
