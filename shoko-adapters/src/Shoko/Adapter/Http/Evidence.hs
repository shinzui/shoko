module Shoko.Adapter.Http.Evidence (HttpFailure (..), failureCode) where

import Shoko.Prelude

data HttpFailure = EndpointNotAllowed | HttpDeadlineExpired | TransportUnavailable | ResponseTooLarge | ResponseUndecodable | HttpCorrelationUnavailable | InvalidHttpInput
  deriving stock (Eq, Show, Generic)

failureCode :: HttpFailure -> Text
failureCode EndpointNotAllowed = "http-endpoint-not-allowed"
failureCode HttpDeadlineExpired = "http-deadline-expired"
failureCode TransportUnavailable = "http-transport-unavailable"
failureCode ResponseTooLarge = "http-response-too-large"
failureCode ResponseUndecodable = "http-response-undecodable"
failureCode HttpCorrelationUnavailable = "http-correlation-unavailable"
failureCode InvalidHttpInput = "invalid-http-input"
