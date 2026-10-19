{-# LANGUAGE RankNTypes #-}

module Shoko.Internal.Binding where

import Data.Set (Set)
import Shoko.Action
import Shoko.Clock
import Shoko.Environment
import Shoko.Identifier
import Shoko.Internal.Call
import Shoko.Observation
import Shoko.Prelude

data BindingContract = BindingContract !(Set Capability) !(Set Capability)
  deriving stock (Eq, Show, Generic)

data Disposition = Cleaned | Retained | CleanupFailed | CleanupTimedOut
  deriving stock (Eq, Show, Generic)

data HandlerBuildError
  = EndpointNotAllowlisted !Text
  | ObservationMethodNotGet !Text
  | ObservationScopeMissing !Text
  | ExecutionMetadataUnsupported
  deriving stock (Eq, Show, Generic)

data CorrelationRequirement = RequiresBusinessKey !BusinessKeyName | RequiresExecutionId
  deriving stock (Eq, Show, Generic)

-- The structural owner path distinguishes independently acquired sources.
data Source resource
  = Source
      !SourceId
      !CoverageStrength
      (resource -> Clock -> IO (Either Text Baseline))
      ![Bool]

data Handler resource a
  = ActionHandler !BindingContract (resource -> CallContext -> IO (ActionOutcome a))
  | ObservationHandler
      !BindingContract
      !CorrelationRequirement
      !(Source resource)
      (resource -> CallContext -> IO (ObservationOutcome a))

data HandlerKind = ActionHandlerKind | ObservationHandlerKind
  deriving stock (Eq, Show, Generic)

data Binding op resource = Binding
  { internalName :: !Text,
    internalLifecycle :: !(Set Capability),
    internalAcquire :: (IO Disposition -> IO ()) -> IO resource,
    internalRelease :: resource -> [IO Disposition],
    internalHandler :: forall a. OperationRole -> op a -> Either HandlerBuildError (Maybe (Handler resource a))
  }
