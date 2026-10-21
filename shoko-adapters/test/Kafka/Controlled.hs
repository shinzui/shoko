-- | An in-memory, read-committed topic behind the scanner port. It models
-- offsets, low watermarks, open/committed/aborted transactions with control
-- records, partitions that never report EOF, and injected client failures.
module Kafka.Controlled
  ( Controlled,
    Entry (..),
    newControlled,
    port,
    produce,
    produceTo,
    begin,
    commit,
    abort,
    truncateBefore,
    addPartition,
    removeTopic,
    neverEnds,
    overrideWatermarks,
    failWith,
    blockReads,
    duringRead,
    readCalls,
    record,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.IORef
import Data.Int (Int32, Int64)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Time (UTCTime)
import Shoko.Adapter.Kafka.Internal

data Status = Committed | Open | Aborted | Marker deriving stock (Eq)

data Entry = Entry !Status !KafkaRecord

data Partition = Partition
  { low :: !Int64,
    entries :: ![Entry]
  }

data Controlled = Controlled
  { partitions :: !(IORef (Maybe (Map Int32 Partition))),
    endless :: !(IORef (Set Int32)),
    failure :: !(IORef (Maybe KafkaFailure)),
    blocked :: !(IORef Bool),
    hook :: !(IORef (IO ())),
    reported :: !(IORef (Map Int32 Watermarks)),
    calls :: !(IORef Int)
  }

newControlled :: Int32 -> IO Controlled
newControlled count =
  Controlled
    <$> newIORef (Just (Map.fromList [(p, Partition 0 []) | p <- [0 .. count - 1]]))
    <*> newIORef Set.empty
    <*> newIORef Nothing
    <*> newIORef False
    <*> newIORef (pure ())
    <*> newIORef Map.empty
    <*> newIORef 0

record :: UTCTime -> Maybe ByteString -> [(ByteString, ByteString)] -> Maybe ByteString -> KafkaRecord
record timestamp = KafkaRecord 0 (Just timestamp)

nextOffset :: Partition -> Int64
nextOffset (Partition lowOffset stored) = lowOffset + fromIntegral (length stored)

-- Offsets are positional: retained entries are contiguous from the low watermark.
append :: Controlled -> Int32 -> Status -> KafkaRecord -> IO Int64
append controlled partition status value = atomicModifyIORef' (partitions controlled) $ \case
  Just topic
    | Just existing <- Map.lookup partition topic ->
        let offset = nextOffset existing
            stored = Entry status value {recordOffset = offset}
         in (Just (Map.insert partition existing {entries = entries existing ++ [stored]} topic), offset)
  other -> (other, -1)

produce :: Controlled -> KafkaRecord -> IO Int64
produce controlled = produceTo controlled 0

produceTo :: Controlled -> Int32 -> KafkaRecord -> IO Int64
produceTo controlled partition = append controlled partition Committed

-- | Write a record inside a transaction that stays open until 'commit' or 'abort'.
begin :: Controlled -> Int32 -> KafkaRecord -> IO Int64
begin controlled partition = append controlled partition Open

finish :: Status -> Controlled -> Int32 -> IO ()
finish outcome controlled partition = do
  modifyIORef' (partitions controlled) . fmap $ Map.adjust (\existing -> existing {entries = map settle (entries existing)}) partition
  marker <- readIORef (partitions controlled)
  case marker >>= Map.lookup partition of
    Just (Partition _ (Entry _ template : _)) -> () <$ append controlled partition Marker template
    _ -> pure ()
  where
    settle (Entry Open value) = Entry outcome value
    settle other = other

commit :: Controlled -> Int32 -> IO ()
commit = finish Committed

abort :: Controlled -> Int32 -> IO ()
abort = finish Aborted

-- | Retention deletion: the low watermark moves to the given offset.
truncateBefore :: Controlled -> Int32 -> Int64 -> IO ()
truncateBefore controlled partition offset =
  modifyIORef' (partitions controlled) . fmap $ Map.adjust (\(Partition lowOffset stored) -> Partition (max lowOffset offset) (drop (fromIntegral (offset - lowOffset)) stored)) partition

addPartition :: Controlled -> IO ()
addPartition controlled = modifyIORef' (partitions controlled) . fmap $ \topic -> Map.insert (fromIntegral (Map.size topic)) (Partition 0 []) topic

removeTopic :: Controlled -> IO ()
removeTopic controlled = writeIORef (partitions controlled) Nothing

neverEnds :: Controlled -> Int32 -> IO ()
neverEnds controlled partition = modifyIORef' (endless controlled) (Set.insert partition)

-- | Report these watermarks instead of the modelled ones, as a broker whose
-- log was replaced or rewound would.
overrideWatermarks :: Controlled -> Int32 -> Maybe Watermarks -> IO ()
overrideWatermarks controlled partition = modifyIORef' (reported controlled) . maybe (Map.delete partition) (Map.insert partition)

failWith :: Controlled -> Maybe KafkaFailure -> IO ()
failWith controlled = writeIORef (failure controlled)

blockReads :: Controlled -> IO ()
blockReads controlled = writeIORef (blocked controlled) True

-- | Run once, between the first partition read and the closing metadata check.
duringRead :: Controlled -> IO () -> IO ()
duringRead controlled = writeIORef (hook controlled)

readCalls :: Controlled -> IO Int
readCalls controlled = readIORef (calls controlled)

-- | The read-committed end: the first offset of the earliest open transaction.
visibleEnd :: Partition -> Int64
visibleEnd existing@(Partition lowOffset stored) = case [offset | Entry Open (KafkaRecord offset _ _ _ _) <- stored] of
  first : _ -> first
  [] -> max lowOffset (nextOffset existing)

port :: Controlled -> KafkaPort
port controlled = KafkaPort listPartitions watermarks readFrom
  where
    guardFailure :: IO (Either KafkaFailure a) -> IO (Either KafkaFailure a)
    guardFailure action =
      readIORef (failure controlled) >>= \case
        Just err -> pure (Left err)
        Nothing -> action
    lookupPartition partition =
      readIORef (partitions controlled) >>= \case
        Nothing -> pure (Left KafkaTopicMissing)
        Just topic -> pure (maybe (Left KafkaUnavailable) Right (Map.lookup partition topic))
    listPartitions _ _ _ = guardFailure $ maybe (Left KafkaTopicMissing) (Right . Map.keys) <$> readIORef (partitions controlled)
    watermarks _ _ _ partition = guardFailure $ do
      forced <- Map.lookup partition <$> readIORef (reported controlled)
      fmap (\existing -> maybe (Watermarks (low existing) (visibleEnd existing)) id forced) <$> lookupPartition partition
    readFrom _ _ _ partition start limit = guardFailure $ do
      modifyIORef' (calls controlled) (+ 1)
      stalled <- readIORef (blocked controlled)
      if stalled then forever (threadDelay 1000000) else pure ()
      found <- lookupPartition partition
      action <- atomicModifyIORef' (hook controlled) (\run -> (pure (), run))
      action
      ended <- not . Set.member partition <$> readIORef (endless controlled)
      pure $ case found of
        Left err -> Left err
        Right existing ->
          let end = visibleEnd existing
              visible = [value | Entry Committed value@(KafkaRecord offset _ _ _ _) <- entries existing, offset >= start, offset < end]
           in Right (PartitionRead (take limit visible) (ended && length visible <= limit))
