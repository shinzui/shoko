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
    }
