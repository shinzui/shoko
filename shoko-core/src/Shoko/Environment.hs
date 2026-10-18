module Shoko.Environment
  ( Capability (..),
    Duration,
    milliseconds,
    durationMicros,
    Policy (..),
    defaultPolicy,
    Environment (..),
    RunOptions (..),
    TargetIdentity (..),
  )
where

import Data.Set (Set)
import Shoko.Prelude

data Capability = ReadState | ReadEvents | WriteState | SendHttp | ExternalSideEffect | SyntheticResource
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | Positive, bounded microseconds. The constructor is private.
newtype Duration = Duration Int
  deriving stock (Eq, Ord, Show)

milliseconds :: Int -> Either Text Duration
milliseconds n
  | n <= 0 || n > maxBound `div` 1000 = Left "duration must be positive and representable"
  | otherwise = Right (Duration (n * 1000))

durationMicros :: Duration -> Int
durationMicros (Duration n) = n

data Policy = Policy
  { executionBudget :: !Duration,
    eventuallyWindow :: !Duration,
    pollInterval :: !Duration,
    cleanupGrace :: !Duration
  }
  deriving stock (Eq, Show, Generic)

defaultPolicy :: Policy
defaultPolicy = Policy (Duration 30000000) (Duration 10000000) (Duration 100000) (Duration 5000000)

data Environment = Environment
  { name :: !Text,
    production :: !Bool,
    allowedCapabilities :: !(Set Capability),
    policy :: !Policy
  }
  deriving stock (Eq, Show, Generic)

-- | Host-supplied identity. Core never discovers Kubernetes resources.
data TargetIdentity = TargetIdentity
  { target :: !Text,
    namespaceUid :: !Text,
    deploymentRevision :: !Text
  }
  deriving stock (Eq, Show, Generic)

data RunOptions = RunOptions
  { runId :: !Text,
    allowSynthetic :: !Bool,
    buildIdentity :: !Text,
    implementationIdentity :: !(Maybe Text),
    targetIdentity :: !(Maybe TargetIdentity)
  }
  deriving stock (Eq, Show, Generic)
