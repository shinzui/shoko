{-# LANGUAGE RankNTypes #-}

module Shoko.Clock (Clock (..), realClock, newFakeClock) where

import Control.Concurrent (threadDelay)
import Data.IORef
import Data.Time (UTCTime, addUTCTime, getCurrentTime)
import GHC.Clock (getMonotonicTimeNSec)
import System.Timeout (timeout)

data Clock = Clock
  { monotonic :: IO Integer,
    utc :: IO UTCTime,
    sleepUntil :: Integer -> IO (),
    bounded :: forall a. Integer -> IO a -> IO (Maybe a)
  }

realClock :: Clock
realClock = Clock now getCurrentTime sleep bound
  where
    now = (`div` 1000) . toInteger <$> getMonotonicTimeNSec
    sleep targetTime = do
      current <- now
      let remaining = targetTime - current
      if remaining > 0 then threadDelay (toInt remaining) else pure ()
    bound :: Integer -> IO a -> IO (Maybe a)
    bound targetTime action = do
      current <- now
      if current > targetTime then pure Nothing else timeout (max 1 (toInt (targetTime - current))) action

-- | Deterministic semantic clock. The returned advance function is for test
-- handlers. A real timeout still bounds accidentally blocking test IO.
newFakeClock :: UTCTime -> IO (Clock, Integer -> IO ())
newFakeClock epoch = do
  ticks <- newIORef 0
  let now = readIORef ticks
      advance delta = atomicModifyIORef' ticks (\current -> (current + max 0 delta, ()))
      sleep targetTime = atomicModifyIORef' ticks (\current -> (max current targetTime, ()))
      wall = (\current -> addUTCTime (fromInteger current / 1000000) epoch) <$> now
      bound :: Integer -> IO a -> IO (Maybe a)
      bound targetTime action = do
        current <- now
        if current > targetTime
          then pure Nothing
          else do
            result <- timeout (max 100000 (toInt (targetTime - current))) action
            finished <- now
            pure (if finished <= targetTime then result else Nothing)
  pure (Clock now wall sleep bound, advance)

toInt :: Integer -> Int
toInt = fromInteger . min (toInteger (maxBound :: Int)) . max 0
