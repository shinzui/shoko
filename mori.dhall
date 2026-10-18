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
          , Schema.Dependency.ByName "effectful/effectful:effectful-core"
          , Schema.Dependency.ByName "haskell/aeson:aeson"
          , Schema.Dependency.ByName "simonmar/async:async"
          , Schema.Dependency.ByName "haskell-hvr/cryptohash-sha256:cryptohash-sha256"
          , Schema.Dependency.ByName "haskell/bytestring:bytestring"
          , Schema.Dependency.ByName "haskell/time:time"
          , Schema.Dependency.ByName "UnkindPartition/tasty:tasty"
          , Schema.Dependency.ByName "UnkindPartition/tasty:tasty-hedgehog"
          , Schema.Dependency.ByName "hedgehogqa/haskell-hedgehog:hedgehog"
          ]
        }
      , Schema.Package::{
        , name = "shoko-adapters"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "shoko-adapters"
        , description = Some "Scoped SQL and bounded HTTP evidence adapters"
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/shoko:shoko-core"
          , Schema.Dependency.ByName "hasql/hasql:hasql"
          , Schema.Dependency.ByName "snoyberg/http-client:http-client"
          , Schema.Dependency.ByName "snoyberg/http-client:http-client-tls"
          , Schema.Dependency.ByName "Vlix/http-types:http-types"
          ]
        }
      ]
    , dependencyRefs =
      [ Schema.MoriRef::{
        , namespace = "effectful"
        , name = "effectful"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "effectful-core"
        }
      , Schema.MoriRef::{
        , namespace = "haskell"
        , name = "aeson"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "aeson"
        }
      , Schema.MoriRef::{
        , namespace = "simonmar"
        , name = "async"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "async"
        }
      , Schema.MoriRef::{
        , namespace = "haskell-hvr"
        , name = "cryptohash-sha256"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "cryptohash-sha256"
        }
      , Schema.MoriRef::{
        , namespace = "haskell"
        , name = "bytestring"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "bytestring"
        }
      , Schema.MoriRef::{
        , namespace = "haskell"
        , name = "time"
        , kind = Some Schema.MoriArtifactKind.Package
        , key = Some "time"
        }
      , Schema.MoriRef::{
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
        , key = "adapters"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some "Scoped PostgreSQL queries and bounded HTTP transport"
        , location = Schema.DocLocation.LocalFile "docs/adapters.md"
        }
      , Schema.DocRef::{
        , key = "core"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some "Typed descriptions, binding policy, bounded evidence, and result v1"
        , location = Schema.DocLocation.LocalFile "docs/core.md"
        }
      , Schema.DocRef::{
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
