-- | Bounded, read-only Kafka topic evidence. A reader never joins a consumer
-- group, commits offsets, or creates topics. Allocate one reader per finite run
-- with 'kafka'; broker IO starts only at the source's pre-action baseline.
module Shoko.Adapter.Kafka
  ( Kafka,
    KafkaSettings,
    kafkaSettings,
    kafka,
    kafkaObservation,
    observeKafka,
    module Shoko.Adapter.Kafka.Evidence,
  )
where

import Shoko.Adapter.Kafka.Evidence
import Shoko.Adapter.Kafka.Internal
