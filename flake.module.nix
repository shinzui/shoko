{ ... }:
{
  perSystem = { pkgs, ... }:
    let
      schemaPython = pkgs.python3.withPackages (packages: [ packages.jsonschema ]);
      hs = pkgs.haskell.packages.ghc9124.override {
        overrides = hself: _hsuper: {
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
        };
      };
    in
    {
      haskellProject.extraDevPackages = [ schemaPython ];
      packages.default = hs.shoko-core;
      packages.shoko-core = hs.shoko-core;
      packages.shoko-adapters = hs.shoko-adapters;
      checks.shoko-core = hs.shoko-core;
      checks.shoko-adapters = hs.shoko-adapters;
      checks.result-schema = pkgs.runCommand "shoko-result-schema" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${./scripts/check-result-schema.py} ${./schemas/run-result-v1.schema.json} ${./shoko-core/test/golden}
        touch "$out"
      '';
    };
}
