module Shoko.Internal.Digest (descriptionDigest) where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Set qualified as Set
import Data.Text qualified as Text
import Numeric (showHex)
import Shoko.Action
import Shoko.Environment
import Shoko.Identifier
import Shoko.Observation ()
import Shoko.Prelude
import Shoko.Scenario

-- | SHA-256 of a versioned, fixed-order JSON array of public text fields.
-- Counts delimit every variable-length segment. Literal inputs are absent.
descriptionDigest :: Description -> Text
descriptionDigest (Description key title revision nodes expectations correlations) =
  Text.pack $ concatMap hex $ BS.unpack $ SHA256.hash $ LBS.toStrict $ encode chunks
  where
    chunks =
      ["shoko-description-v3", key, title, revision]
        ++ counted (concatMap node nodes)
        ++ counted (concatMap expectation expectations)
        ++ counted (concatMap declaration correlations)
    counted values = Text.pack (show (length values)) : values
    node (NodeDescription nodeKey fixture info outcomes group) =
      [nodeKey, if fixture then "fixture" else "action"] ++ maybe ["sequential"] (\name -> ["concurrent", name]) group ++ operation info ++ counted (Set.toAscList outcomes)
    expectation (ExpectationDescription expectationKey temporal windows subject predicate selected) =
      [expectationKey, Text.pack (show temporal), predicate] ++ maybe ["none"] (\key' -> ["selected", correlationIdText key']) selected ++ counted (map (Text.pack . show . durationMicros) windows) ++ describeSubject subject
    describeSubject (ObservationSubject info) = "observation" : operation info
    describeSubject (ResultSubject deps) = "result" : counted deps
    declaration (CorrelationDescription identity semantic strategy deps) =
      [correlationIdText identity, businessKeyNameText semantic, Text.pack (show strategy)] ++ counted deps
    operation (OperationInfo opKey caps deps substeps) =
      [opKey]
        ++ counted (map (Text.pack . show) (Set.toAscList caps))
        ++ counted deps
        ++ counted (concatMap (\(step, required) -> step : counted (map (Text.pack . show) (Set.toAscList required))) substeps)
    hex byte = let digits = showHex byte "" in if length digits == 1 then '0' : digits else digits
