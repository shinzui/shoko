{-# LANGUAGE RankNTypes #-}

module Shoko.Clock (Clock (..), MonotonicTime (..), monotonicMicros, addDuration, differenceMicros, realClock, newFakeClock) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Generics (Generic)
import Shoko.Environment (Duration, durationMicros)
import System.Timeout (timeout)

newtype MonotonicTime = MonotonicTime Integer deriving stock (Eq, Ord, Show, Generic)

monotonicMicros :: MonotonicTime -> Integer
monotonicMicros (MonotonicTime value) = value

addDuration :: MonotonicTime -> Duration -> MonotonicTime
addDuration (MonotonicTime tick) duration = MonotonicTime (tick + toInteger (durationMicros duration))

differenceMicros :: MonotonicTime -> MonotonicTime -> Integer
differenceMicros (MonotonicTime later) (MonotonicTime earlier) = later - earlier

data Clock = Clock
  { monotonic :: IO MonotonicTime,
    utc :: IO UTCTime,
    sleepUntil :: MonotonicTime -> IO (),
    bounded :: forall a. MonotonicTime -> IO a -> IO (Maybe a)
  }

realClock :: Clock
realClock = Clock now getCurrentTime sleep bound
  where
    now = MonotonicTime . (`div` 1000) . toInteger <$> getMonotonicTimeNSec
    sleep targetTime = do
      current <- now
      let remaining = differenceMicros targetTime current
      if remaining > 0 then threadDelay (toInt remaining) else pure ()
    bound :: MonotonicTime -> IO a -> IO (Maybe a)
    bound targetTime action = do
      current <- now
      if current > targetTime then pure Nothing else timeout (max 1 (toInt (differenceMicros targetTime current))) action

-- | Deterministic semantic clock. The returned advance function is for test
-- handlers. A real timeout still bounds accidentally blocking test IO.
newFakeClock :: UTCTime -> IO (Clock, Duration -> IO ())
newFakeClock epoch = do
  ticks <- newIORef (MonotonicTime 0)
  let now = readIORef ticks
      advance delta = atomicModifyIORef' ticks (\current -> (addDuration current delta, ()))
      sleep targetTime = atomicModifyIORef' ticks (\current -> (max current targetTime, ()))
      wall = (\current -> addUTCTime (fromInteger (monotonicMicros current) / 1000000) epoch) <$> now
      bound :: MonotonicTime -> IO a -> IO (Maybe a)
      bound targetTime action = do
        current <- now
        if current > targetTime
          then pure Nothing
          else do
            result <- timeout (max 100000 (toInt (differenceMicros targetTime current))) action
            finished <- now
            pure (if finished <= targetTime then result else Nothing)
  pure (Clock now wall sleep bound, advance)

toInt :: Integer -> Int
toInt = fromInteger . min (toInteger (maxBound :: Int)) . max 0
