{ self, ... }:
{
  perSystem = { pkgs, ... }:
    let
      schemaPython = pkgs.python3.withPackages (packages: [ packages.jsonschema ]);
      sourceIdentity = if self ? rev then "${self.rev}-clean" else self.dirtyRev or "source-unrecorded-dirty-state-unknown";
      hs = pkgs.haskell.packages.ghc9124.override {
        overrides = hself: _hsuper: {
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
          shoko-core = pkgs.haskell.lib.appendConfigureFlag
            (hself.callCabal2nix "shoko-core" ./shoko-core { })
            "--ghc-option=-Werror";
          shoko-adapters = (pkgs.haskell.lib.appendConfigureFlag
            (hself.callCabal2nix "shoko-adapters" ./shoko-adapters { })
            "--ghc-option=-Werror").overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 pkgs.postgresql ];
            checkPhase = ''
              runHook preCheck
              python ${./scripts/test-adapters} --binaries dist/build
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
              export SHOKO_RESULT_SCHEMA=${./schemas/run-result-v1.schema.json}
              export SHOKO_DEMO_CONFIG=${./config/demo.yaml}
              python ${./scripts/test-cli} --binaries dist/build
              runHook postCheck
            '';
          });
        };
      };
    in
    {
      haskellProject.extraDevPackages = [ schemaPython ];
      packages.default = hs.shoko-cli;
      packages.shoko-core = hs.shoko-core;
      packages.shoko-adapters = hs.shoko-adapters;
      packages.shoko-cli = hs.shoko-cli;
      checks.shoko-core = hs.shoko-core;
      checks.shoko-adapters = hs.shoko-adapters;
      checks.shoko-cli = hs.shoko-cli;
      checks.result-schema = pkgs.runCommand "shoko-result-schema" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${./scripts/check-result-schema.py} ${./schemas/run-result-v1.schema.json} ${./shoko-core/test/golden}
        touch "$out"
      '';
      checks.workflow-contract = pkgs.runCommand "shoko-workflow-contract" { nativeBuildInputs = [ schemaPython ]; } ''
        cp -R ${./scripts} scripts
        mkdir -p schemas integration/examples
        cp ${./schemas/workflow-v1.schema.json} schemas/workflow-v1.schema.json
        cp ${./integration/examples/workflow.example.json} integration/examples/workflow.example.json
        python scripts/test-workflow-contract
        touch "$out"
      '';
    };
}
