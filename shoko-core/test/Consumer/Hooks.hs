{-# LANGUAGE RankNTypes #-}

module Consumer.Hooks (Hooks (..), newMicroClock) where

import Data.IORef
import Data.Time (UTCTime, addUTCTime)
import Shoko
import Shoko.Clock (Clock (..))
import Shoko.Prelude (Text)
import System.Timeout (timeout)

-- Fixture-owned IO hooks let failure tests alter resources without opening core abstractions.
data Hooks op resource
  = Hooks
      ((IO Disposition -> IO ()) -> IO resource)
      (resource -> IO Disposition)
      (resource -> Clock -> SourceId -> IO (Either Text Baseline))
      (forall a. resource -> CallContext -> op a -> IO (ActionOutcome a))
      (forall a. resource -> CallContext -> op a -> IO (ObservationOutcome a))

-- A microsecond test clock keeps boundary probes finer than public Duration's millisecond precision.
newMicroClock :: UTCTime -> IO (Clock, Integer -> IO ())
newMicroClock epoch = do
  ticks <- newIORef (MonotonicTime 0)
  let now = readIORef ticks
      advance delta = modifyIORef' ticks (\tick -> MonotonicTime (monotonicMicros tick + max 0 delta))
      sleep end = modifyIORef' ticks (max end)
      wall = (\tick -> addUTCTime (fromInteger (monotonicMicros tick) / 1000000) epoch) <$> now
      bound :: MonotonicTime -> IO a -> IO (Maybe a)
      bound end action = do
        current <- now
        if current > end
          then pure Nothing
          else do
            answer <- timeout (max 100000 (fromInteger (differenceMicros end current))) action
            finished <- now
            pure (if finished <= end then answer else Nothing)
  pure (Clock now wall sleep bound, advance)
