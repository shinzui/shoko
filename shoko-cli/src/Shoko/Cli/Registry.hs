module Shoko.Cli.Registry (Registry (..), Entry (..), SomeBinding (..)) where

import Shoko
import Shoko.Cli.Config
import Shoko.Prelude
import Shoko.Result (LogicalInput)

data SomeBinding op = forall resource. SomeBinding !(Binding op resource)

-- | Factories must construct metadata without IO and defer credential access
-- to their acquisition/handlers. The CLI resolves live secrets before effects.
data Entry
  = forall op. (Vocabulary op) => Entry
      !(Scenario op)
      !LogicalInput
      ![(Text, HostConfig -> Maybe Credentials -> SomeBinding op)]
      !(HostConfig -> IO (Either Text (Maybe Text, Maybe TargetIdentity)))

data Registry = Registry
  {environments :: ![Text], entries :: ![Entry]}
