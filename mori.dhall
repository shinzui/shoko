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
        , description = Some
            "Public core library and bounded verification runner"
        , dependencies =
          [ Schema.Dependency.ByName "haskell/text:text"
          , Schema.Dependency.ByName "haskell/containers:containers"
          , Schema.Dependency.ByName "effectful/effectful:effectful-core"
          , Schema.Dependency.ByName "haskell/aeson:aeson"
          , Schema.Dependency.ByName "simonmar/async:async"
          , Schema.Dependency.ByName
              "haskell-hvr/cryptohash-sha256:cryptohash-sha256"
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
        , description = Some
            "Scoped SQL, HTTP, Kiroku, Message DB, and Kafka topic evidence adapters"
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/shoko:shoko-core"
          , Schema.Dependency.ByName "haskell/aeson:aeson"
          , Schema.Dependency.ByName "haskell/time:time"
          , Schema.Dependency.ByName "haskell-hvr/uuid:uuid"
          , Schema.Dependency.ByName "haskell/vector:vector"
          , Schema.Dependency.ByName "shinzui/kiroku:kiroku-store"
          , Schema.Dependency.ByName "hasql/hasql:postgresql-connection-string"
          , Schema.Dependency.ByName "hasql/hasql:hasql"
          , Schema.Dependency.ByName "snoyberg/http-client:http-client"
          , Schema.Dependency.ByName "snoyberg/http-client:http-client-tls"
          , Schema.Dependency.ByName "Vlix/http-types:http-types"
          ]
        }
      , Schema.Package::{
        , name = "shoko-cli"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "shoko-cli"
        , description = Some
            "Reusable compiled scenario CLI host and labelled demo executable"
        , dependencies =
          [ Schema.Dependency.ByName "shinzui/shoko:shoko-core"
          , Schema.Dependency.ByName "shinzui/settei:settei"
          , Schema.Dependency.ByName "shinzui/settei:settei-yaml"
          , Schema.Dependency.ByName "shinzui/settei:settei-env"
          , Schema.Dependency.ByName
              "shinzui/settei:settei-optparse-applicative"
          , Schema.Dependency.ByName
              "pcapriotti/optparse-applicative:optparse-applicative"
          , Schema.Dependency.ByName "snoyberg/githash:githash"
          , Schema.Dependency.ByName "haskell/directory:directory"
          , Schema.Dependency.ByName "haskell/filepath:filepath"
          , Schema.Dependency.ByName "haskell/unix:unix"
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
        , key = "generic-staging-contract"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some "Workflow v2 structure, bounded read-only readiness and the shared target observation protocol"
        , location = Schema.DocLocation.LocalFile "docs/workflows/generic-staging-contract.md"
        }
      , Schema.DocRef::{
        , key = "scenario-catalog"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some "Strict catalog validation and explicit compiled-host inspection"
        , location = Schema.DocLocation.LocalFile "docs/scenario-catalog.md"
        }
      , Schema.DocRef::{
        , key = "scenario-hosts"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some
            "Compiled domain hosts, strict configuration, process exits, and atomic reports"
        , location = Schema.DocLocation.LocalFile "docs/scenario-hosts.md"
        }
      , Schema.DocRef::{
        , key = "adapters"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some
            "Scoped SQL/HTTP and finite Kiroku/Message DB evidence readers"
        , location = Schema.DocLocation.LocalFile "docs/adapters.md"
        }
      , Schema.DocRef::{
        , key = "core"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some
            "Typed descriptions, binding policy, bounded evidence, and result v2"
        , location = Schema.DocLocation.LocalFile "docs/core.md"
        }
      , Schema.DocRef::{
        , key = "development"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Build, test, format, and maintain the Shoko workspace"
        , location = Schema.DocLocation.LocalFile "docs/development.md"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "capabilities"
        , path = "docs/capabilities"
        , profileBinding = Some
            ( Schema.ProfileBinding.Published
                Schema.PinnedImport::{
                , publisher = "mori://shinzui/okf-profiles"
                , publisherRef = Some Schema.MoriRef::{
                  , namespace = "shinzui"
                  , name = "okf-profiles"
                  }
                , export = Some "coordination.capabilities"
                , version = Some "v0.21.0"
                , pin = Some
                    "sha256:4be32588d55c74282ceab54b06b22f552cdbf4215788e3eb5256ee8744cb92a2"
                }
            )
        , okfVersion = "0.2"
        , description = Some
            "Implemented consumer capabilities with stable CAP handles, evidence, and limits"
        }
      , Schema.OkfBundle::{
        , name = "terminology"
        , path = "docs/terminology"
        , profileBinding = Some
            ( Schema.ProfileBinding.Published
                Schema.PinnedImport::{
                , publisher = "mori://shinzui/okf-profiles"
                , publisherRef = Some Schema.MoriRef::{
                  , namespace = "shinzui"
                  , name = "okf-profiles"
                  }
                , export = Some "documentation.terminology"
                , version = Some "v0.21.0"
                , pin = Some
                    "sha256:4be32588d55c74282ceab54b06b22f552cdbf4215788e3eb5256ee8744cb92a2"
                }
            )
        , okfVersion = "0.2"
        , description = Some
            "Controlled Shoko vocabulary with stable TERM handles and source anchors"
        }
      , Schema.OkfBundle::{
        , name = "improvement-requests"
        , path = "docs/improvement-requests"
        , profileBinding = Some
            ( Schema.ProfileBinding.Published
                Schema.PinnedImport::{
                , publisher = "mori://shinzui/okf-profiles"
                , publisherRef = Some Schema.MoriRef::{
                  , namespace = "shinzui"
                  , name = "okf-profiles"
                  }
                , export = Some "coordination.improvementRequests"
                , version = Some "v0.22.0"
                , pin = Some
                    "sha256:2294a5bd32ca22daa89610e12fde81dd3115701fcb0bf7a790c7bdee6d85db65"
                }
            )
        , okfVersion = "0.2"
        , description = Some
            "Cross-repository improvement requests raised against Shoko, with stable IR handles"
        }
      , Schema.OkfBundle::{
        , name = "research"
        , path = "docs/research"
        , profile = Some "docs/research/profile.dhall"
        , okfVersion = "0.2"
        , description = Some
            "Bounded investigations that validate and inform the Shōko specification and design"
        }
      ]
    }
