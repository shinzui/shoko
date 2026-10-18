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
import Shoko.Observation ()
import Shoko.Prelude
import Shoko.Scenario

-- | SHA-256 of a versioned, fixed-order JSON array of public text fields.
-- Counts delimit every variable-length segment. Literal inputs are absent.
descriptionDigest :: Description -> Text
descriptionDigest (Description key title revision nodes expectations) =
  Text.pack $ concatMap hex $ BS.unpack $ SHA256.hash $ LBS.toStrict $ encode chunks
  where
    chunks =
      ["shoko-description-v1", key, title, revision]
        ++ counted (concatMap node nodes)
        ++ counted (concatMap expectation expectations)
    counted values = Text.pack (show (length values)) : values
    node (NodeDescription nodeKey fixture info outcomes) =
      [nodeKey, if fixture then "fixture" else "action"] ++ operation info ++ counted (Set.toAscList outcomes)
    expectation (ExpectationDescription expectationKey temporal windows info predicate) =
      [expectationKey, Text.pack (show temporal), predicate] ++ counted (map (Text.pack . show . durationMicros) windows) ++ operation info
    operation (OperationInfo opKey caps deps substeps) =
      [opKey]
        ++ counted (map (Text.pack . show) (Set.toAscList caps))
        ++ counted deps
        ++ counted (concatMap (\(step, required) -> step : counted (map (Text.pack . show) (Set.toAscList required))) substeps)
    hex byte = let digits = showHex byte "" in if length digits == 1 then '0' : digits else digits
