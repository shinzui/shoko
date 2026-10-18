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
        };
      };
    in
    {
      haskellProject.extraDevPackages = [ schemaPython ];
      packages.default = hs.shoko-core;
      packages.shoko-core = hs.shoko-core;
      checks.shoko-core = hs.shoko-core;
      checks.result-schema = pkgs.runCommand "shoko-result-schema" { nativeBuildInputs = [ schemaPython ]; } ''
        python ${./scripts/check-result-schema.py} ${./schemas/run-result-v1.schema.json} ${./shoko-core/test/golden}
        touch "$out"
      '';
    };
}
