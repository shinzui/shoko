let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/3522f4a51181d73c9c90fc27a7c0838bd29ae95f/package.dhall
        sha256:dcb19e2312e790bad14e622cc98a1281cd2298c5b564a2f0d0534d3c718d8803

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "shoko"
      , namespace = "shinzui"
      , stableId = Some "project_01m3r14vs1exh8gw4fzh6tae5y"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Experimental
      , description = Some
          "Haskell DSL for specifying and verifying observable behavior across distributed systems through environment-independent evidence."
      , domains =
        [ "Testing", "Observability", "DistributedSystems", "EventSourcing" ]
      , owners = [ "shinzui" ]
      }
    , repos = [ Schema.Repo::{ name = "shoko", github = Some "shinzui/shoko" } ]
    , packages =
      [ Schema.Package::{
        , name = "shoko-core"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "shoko-core"
        , description = Some "Public core library and bounded verification runner"
        , dependencies =
          [ Schema.Dependency.ByName "haskell/text:text"
          , Schema.Dependency.ByName "haskell/containers:containers"
          , Schema.Dependency.ByName "UnkindPartition/tasty:tasty"
          , Schema.Dependency.ByName "UnkindPartition/tasty:tasty-hedgehog"
          , Schema.Dependency.ByName "hedgehogqa/haskell-hedgehog:hedgehog"
          ]
        }
      ]
    , dependencyRefs =
      [ Schema.MoriRef::{
        , namespace = "haskell"
        , name = "containers"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "containers"
        }
      , Schema.MoriRef::{
        , namespace = "haskell"
        , name = "text"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "text"
        }
      , Schema.MoriRef::{
        , namespace = "UnkindPartition"
        , name = "tasty"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "tasty"
        }
      , Schema.MoriRef::{
        , namespace = "UnkindPartition"
        , name = "tasty"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "tasty-hedgehog"
        }
      , Schema.MoriRef::{
        , namespace = "hedgehogqa"
        , name = "haskell-hedgehog"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "hedgehog"
        }
      ]
    , docs =
      [ Schema.DocRef::{
        , key = "development"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some "Build, test, format, and maintain the Shoko workspace"
        , location = Schema.DocLocation.LocalFile "docs/development.md"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "research"
        , path = "docs/research"
        , profile = Some "docs/research/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "Bounded investigations that validate and inform the Shōko specification and design"
        }
      ]
    }
