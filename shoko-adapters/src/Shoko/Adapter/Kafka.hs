-- | Bounded, read-only Kafka topic evidence. A reader never joins a consumer
-- group, commits offsets, or creates topics. The released-client spike gates
-- the client-backed constructor (see docs/plans/10); until it passes, readers
-- are built over a controlled port in "Shoko.Adapter.Kafka.Internal".
module Shoko.Adapter.Kafka
  ( Kafka,
    KafkaSettings,
    kafkaSettings,
    kafkaObservation,
    observeKafka,
    module Shoko.Adapter.Kafka.Evidence,
  )
where

import Shoko.Adapter.Kafka.Evidence
import Shoko.Adapter.Kafka.Internal
