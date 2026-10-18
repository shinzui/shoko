{ ... }:
{
  perSystem = { pkgs, ... }:
    let
      hs = pkgs.haskell.packages.ghc9124.override {
        overrides = hself: _hsuper: {
          shoko-core = pkgs.haskell.lib.appendConfigureFlag
            (hself.callCabal2nix "shoko-core" ./shoko-core { })
            "--ghc-option=-Werror";
        };
      };
    in
    {
      packages.default = hs.shoko-core;
      packages.shoko-core = hs.shoko-core;
      checks.shoko-core = hs.shoko-core;
    };
}
