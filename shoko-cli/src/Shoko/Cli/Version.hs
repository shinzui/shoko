{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

module Shoko.Cli.Version (buildIdentity) where

import Data.Text qualified as Text
import Data.Version (showVersion)
#ifndef SHOKO_SOURCE
import GitHash (GitInfo, giDirty, giHash, tGitInfoCwdTry)
#endif
import Paths_shoko_cli (version)
import Shoko.Prelude

#ifndef SHOKO_SOURCE
gitInfo :: Either String GitInfo
gitInfo = $$tGitInfoCwdTry
#endif

buildIdentity :: Text
buildIdentity = "shoko " <> Text.pack (showVersion version) <> " " <> source
  where
#ifdef SHOKO_SOURCE
    source = SHOKO_SOURCE
#else
    source = case gitInfo of
      Right info -> Text.pack (giHash info) <> if giDirty info then " dirty" else " clean"
      Left _ -> "source-unrecorded dirty-state-unknown"
#endif
