module Main (main) where

import Demo (registry)
import Shoko.Cli (runShokoCli)

main :: IO ()
main = runShokoCli registry
