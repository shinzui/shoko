-- | Bounded, read-only Kafka topic evidence. A reader never joins a consumer
-- group, commits offsets, or creates topics. The client-backed constructor
-- arrives with the hw-kafka-client fork pinned by docs/plans/10; until then
-- readers are built over a controlled port in "Shoko.Adapter.Kafka.Internal".
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
