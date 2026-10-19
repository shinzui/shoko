{-# LANGUAGE RankNTypes #-}

module Shoko.Internal.Call where

import Shoko.Clock
import Shoko.Correlation
import Shoko.Internal.Reference
import Shoko.Observation
import Shoko.Prelude

data CallContext = CallContext
  { callResolve :: forall a. Input a -> IO (Either InputResolutionError a),
    callDeadline :: !MonotonicTime,
    callBaseline :: !(Maybe Baseline),
    callCorrelation :: !(Maybe Correlation),
    callSubstep :: forall a. Text -> IO a -> IO (Either Text a),
    callCutoff :: !MonotonicTime,
    callTime :: !Clock,
    callExecutionId :: !(Maybe Text)
  }

detachedCallContext :: Clock -> MonotonicTime -> MonotonicTime -> Maybe Baseline -> Maybe Correlation -> CallContext
detachedCallContext clock end cutoff base selected =
  CallContext (const (pure (Left DetachedInputContext))) end base selected (\_ _ -> pure (Left "detached-substep")) cutoff clock Nothing
