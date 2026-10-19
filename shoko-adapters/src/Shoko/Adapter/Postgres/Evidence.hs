module Shoko.Adapter.Postgres.Evidence (PostgresFailure (..), failureCode, Sample (..)) where

import Shoko.Clock (MonotonicTime)
import Shoko.Prelude

data PostgresFailure = ConnectionUnavailable | PermissionDenied | QueryUnavailable | DecodeUnavailable | DeadlineExpired | CorrelationUnavailable
  deriving stock (Eq, Show, Generic)

failureCode :: PostgresFailure -> Text
failureCode ConnectionUnavailable = "postgres-connection-unavailable"
failureCode PermissionDenied = "postgres-permission-denied"
failureCode QueryUnavailable = "postgres-query-unavailable"
failureCode DecodeUnavailable = "postgres-decode-unavailable"
failureCode DeadlineExpired = "postgres-deadline-expired"
failureCode CorrelationUnavailable = "postgres-correlation-unavailable"

data Sample = Sample {started :: !MonotonicTime, finished :: !MonotonicTime, description :: !Text}
  deriving stock (Eq, Show, Generic)
