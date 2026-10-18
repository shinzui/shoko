-- | Store-neutral finite scan descriptions. Payloads have no rendering instance.
module Shoko.Adapter.EventStore
  ( EventScope (..),
    streamScope,
    categoryScope,
    Limits,
    limits,
    CorrelationMode (..),
    HistoryPolicy (..),
    EventQuery,
    eventQuery,
    EventEvidence (..),
  )
where

import Shoko.Adapter.EventStore.Internal
