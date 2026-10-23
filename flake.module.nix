{ self, ... }:
{
  perSystem = { pkgs, ... }:
    let
      schemaPython = pkgs.python3.withPackages (packages: [ packages.jsonschema ]);
      sourceIdentity = if self ? rev then "${self.rev}-clean" else self.dirtyRev or "source-unrecorded-dirty-state-unknown";
      hs = pkgs.haskell.packages.ghc9124.override {
        overrides = hself: _hsuper: {
          rdkafka-hs = hself.callCabal2nix "rdkafka-hs"
            (pkgs.fetchFromGitHub {
              owner = "shinzui";
              repo = "rdkafka-hs";
              rev = "63031a21d070819fe89afbacb6ce76238816748f";
              hash = "sha256-ndzJox3LOnVwbFV2qkoB9ii9DDINyLuxvrNLXFTxAwQ=";
            })
            { };
          # Released packages newer than the managed all-cabal-hashes snapshot.
          settei = hself.callHackageDirect
            {
              pkg = "settei";
              ver = "0.2.0.0";
              sha256 = "12fdsspr3w5q9lmll12l530grw2vglf8a6ixk8y5pkmf2lqnkvwl";
            }
            { };
          settei-env = hself.callHackageDirect
            {
              pkg = "settei-env";
              ver = "0.2.0.0";
              sha256 = "0d7mcffdrpzfmh00cpgqli6pvpn4wi2k77qb6mbgkcbxkn5n32kp";
            }
            { };
          settei-yaml = hself.callHackageDirect
            {
              pkg = "settei-yaml";
              ver = "0.2.0.0";
              sha256 = "088crzqfhjzydxdsd1mrj4rqnwxx9n5xckd1fp374fa1lbf5lmp6";
            }
            { };
          settei-optparse-applicative = hself.callHackageDirect
            {
              pkg = "settei-optparse-applicative";
              ver = "0.2.0.0";
              sha256 = "00iypw1jgwf3rdin6namlxfmj64llgyfb3v4smkm9s5z2gwjrp16";
            }
            { };
          optparse-applicative = hself.callHackageDirect
            {
              pkg = "optparse-applicative";
              ver = "0.19.0.0";
              sha256 = "0cs8fqipakad38lvm75nz98hmvf881mgjhnc7icblxfzh92ay6kn";
            }
            { };
          # Coherent Hasql 1.10 set required by the released Kiroku API.
          hasql = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "hasql"; ver = "1.10.3.7"; sha256 = "1fd1rkwq7jihkvvbnri4x4aa5rkhf49izljn06jjk4kzqs0x1sbw"; }
            { });
          kiroku-store = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "kiroku-store"; ver = "0.11.0.0"; sha256 = "0z3w2bi4zlrmhlxyd8ihw2jrqnwjj75xyx8ami9174966995zavl"; }
            # Upstream's separate IO/test-support packages are not library inputs.
            # Shoko runs the actual append/read contract against pinned migrations.
            { kiroku-test-support = null; shibuya-core = null; ephemeral-pg = null; });
          hasql-pool = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "hasql-pool"; ver = "1.4.2.3"; sha256 = "1f0ki9slw7lhrwk5ccmwpcmmlanffnxwc02xglfvw4rcl826l9x6"; }
            { });
          hasql-transaction = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "hasql-transaction"; ver = "1.2.3.1"; sha256 = "05jn4ci65sbzi9316rqzy0pz93j2yv0fgzqvicbq61q952fq9mqj"; }
            { pqi = null; pqi-ffi = null; pqi-native = null; testcontainers-postgresql = null; });
          hasql-notifications = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "hasql-notifications"; ver = "0.2.5.0"; sha256 = "11jkrngiy175wc5hqx8pgagj4fdg42ry7afp4g4rr5hw8h43zg48"; }
            { });
          postgresql-binary = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "postgresql-binary"; ver = "0.15.0.1"; sha256 = "02cj87xbhpq4jn0ys3pdscblan69d5f1vcsgb5y2piw310x7d6xb"; }
            { });
          streamly-core = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "streamly-core"; ver = "0.3.1"; sha256 = "1bk9m7h0kar6nipq36kxdhxh9g48v5828qcygxpcjdh6pqipxn4k"; }
            { });
          mmzk-typeid = pkgs.haskell.lib.dontCheck (hself.callHackageDirect
            { pkg = "mmzk-typeid"; ver = "0.7.1.2"; sha256 = "0rwawa7zrqqhld83y6h64v3010y8wray6kw94vp2ah4m7al9wicc"; }
            { });
          shoko-core = pkgs.haskell.lib.appendConfigureFlag
            (hself.callCabal2nix "shoko-core" ./shoko-core { })
            "--ghc-option=-Werror";
          shoko-adapters = (pkgs.haskell.lib.appendConfigureFlag
            (hself.callCabal2nix "shoko-adapters" ./shoko-adapters { })
            "--ghc-option=-Werror").overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 pkgs.postgresql pkgs.apacheKafka ];
            checkPhase = ''
              runHook preCheck
              SHOKO_TEST_SMOKE_WRAPPER=${./scripts/smoke-email} SHOKO_TEST_EMAIL_HOST_CHECK=${./scripts/test-email-host} python -P ${./scripts/test-email} --binaries dist/build
              python ${./scripts/test-adapters} --binaries dist/build
              python ${./scripts/test-event-stores} --binaries dist/build
              python ${./scripts/test-kafka} --binaries dist/build
              runHook postCheck
            '';
          });
          shoko-cli = (pkgs.haskell.lib.appendConfigureFlags
            (hself.callCabal2nix "shoko-cli" ./shoko-cli { })
            [ "--ghc-option=-Werror" "--ghc-option=-DSHOKO_SOURCE=\"${sourceIdentity}\"" ]).overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ schemaPython ];
            meta = (old.meta or { }) // { mainProgram = "shoko"; };
            checkPhase = ''
              runHook preCheck
              export SHOKO_CONFIG_SCHEMA=${./schemas/config-v1.schema.json}
              export SHOKO_RESULT_SCHEMA=${./schemas/run-result-v2.schema.json}
              export SHOKO_DEMO_CONFIG=${./config/demo.yaml}
              python ${./scripts/test-cli} --binaries dist/build
              runHook postCheck
            '';
          });
        };
      };
      suiteSource = pkgs.runCommand "shoko-suite-source" { } ''
        mkdir -p "$out/scripts" "$out/schemas"
        cp ${./scripts/shoko-suite} "$out/scripts/shoko-suite"
        cp ${./scripts/scenario_catalog.py} "$out/scripts/scenario_catalog.py"
        cp ${./schemas/scenario-catalog-v1.schema.json} "$out/schemas/scenario-catalog-v1.schema.json"
      '';
      suite = pkgs.writeShellApplication {
        name = "shoko-suite";
        runtimeInputs = [ schemaPython ];
        text = ''exec python3 ${suiteSource}/scripts/shoko-suite "$@"'';
      };
      workflowSource = pkgs.runCommand "shoko-workflow-source" { } ''
        mkdir -p "$out/scripts" "$out/schemas" "$out/integration/examples"
        cp ${./scripts/shoko-workflow} "$out/scripts/shoko-workflow"
        cp ${./scripts/workflow_v2.py} "$out/scripts/workflow_v2.py"
        cp ${./scripts/workflow_probe.py} "$out/scripts/workflow_probe.py"
        cp ${./scripts/workflow_contract.py} "$out/scripts/workflow_contract.py"
        cp ${./scripts/workflow_identity.py} "$out/scripts/workflow_identity.py"
        cp ${./scripts/test-workflow-v2} "$out/scripts/test-workflow-v2"
        cp ${./schemas/workflow-v1.schema.json} "$out/schemas/workflow-v1.schema.json"
        cp ${./schemas/workflow-v2.schema.json} "$out/schemas/workflow-v2.schema.json"
        cp ${./schemas/target-observation-v1.schema.json} "$out/schemas/target-observation-v1.schema.json"
        cp ${./integration/examples/workflow.example.json} "$out/integration/examples/workflow.example.json"
        cp ${./integration/examples/notification-workflow.example.json} "$out/integration/examples/notification-workflow.example.json"
      '';
      workflow = pkgs.writeShellApplication {
        name = "shoko-workflow";
        runtimeInputs = [ schemaPython pkgs.kubectl ];
        text = ''exec python3 ${workflowSource}/scripts/shoko-workflow "$@"'';
      };
    in
    {
      haskellProject.extraDevPackages = [ schemaPython pkgs.apacheKafka pkgs.haskell.packages.ghc9124.c2hs ];
      packages.default = hs.shoko-cli;
      packages.shoko-core = hs.shoko-core;
      packages.shoko-adapters = hs.shoko-adapters;
      packages.shoko-cli = hs.shoko-cli;
      packages.shoko-suite = suite;
      packages.shoko-workflow = workflow;
      checks.workflow-v2 = pkgs.runCommand "shoko-workflow-v2" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${workflowSource}/scripts/test-workflow-v2
        touch "$out"
      '';
      checks.scenario-catalog = pkgs.runCommand "shoko-scenario-catalog" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${./scripts/test-scenario-catalog} --suite ${suiteSource} --host ${hs.shoko-cli}/bin/shoko-consumer-host
        touch "$out"
      '';
      checks.shoko-core = hs.shoko-core;
      checks.shoko-adapters = hs.shoko-adapters;
      checks.shoko-cli = hs.shoko-cli;
      checks.result-schema = pkgs.runCommand "shoko-result-schema" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${./scripts/check-result-schema.py} ${./schemas/run-result-v2.schema.json} ${./shoko-core/test/golden}
        touch "$out"
      '';
      checks.workflow-contract = pkgs.runCommand "shoko-workflow-contract" { nativeBuildInputs = [ schemaPython ]; } ''
        cp -R ${./scripts} scripts
        mkdir -p schemas integration/examples
        cp ${./schemas/workflow-v1.schema.json} schemas/workflow-v1.schema.json
        cp ${./integration/examples/workflow.example.json} integration/examples/workflow.example.json
        python scripts/test-workflow-contract
        python scripts/test-workflow-identity
        touch "$out"
      '';
    };
}
