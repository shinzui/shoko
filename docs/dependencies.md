# Dependency selection

Verified on 2026-10-18 against Hackage JSON release listings and upstream tags,
after locating APIs through Mori. Hackage is authoritative for released Cabal
metadata; local corpus checkouts are API research, not pins. Package bounds in
the Cabal manifest express supported release families; the project constraints,
freeze file, and Nix lock establish the accepted selection.

| Package | Selected | Latest Hackage release observed | Canonical owner | Upstream release revision |
| --- | --- | --- | --- | --- |
| text | 2.1.4 (GHC boot package) | 2.1.4 | [text](mori://haskell/text/packages/text) | `423fd981e576bd17a8b5fa48d0ad6b9a0c370e77` (2.1.4) |
| containers | 0.7 (GHC boot package) | 0.8.1 | [containers](mori://haskell/containers/packages/containers) | `4fda06c43ea14f808748aa8988158946c3ce0caf` (v0.7) |
| tasty | 1.5.4 | 1.5.4 | [Tasty](mori://UnkindPartition/tasty/packages/tasty) | `0394c73e647834829e7f500c9dab0be3ff9e4f11` (core-1.5.4) |
| hedgehog | 1.5 | 1.7 | [Hedgehog](mori://hedgehogqa/haskell-hedgehog/packages/hedgehog) | `4c5424db30eee67423ddd80745d03e487a223ade` (1.5); latest 1.7 is `947e0806579778fb2e28d62afb30d6e61214244c` |
| tasty-hedgehog | 1.4.0.2 | 1.4.0.2 | [Tasty Hedgehog](mori://UnkindPartition/tasty/packages/tasty-hedgehog) | `3d46b53a00b39722627a7697cff93240f21d4cb1` (1.4.0.2) |

Registry release listings: [text](https://hackage.haskell.org/package/text.json),
[tasty](https://hackage.haskell.org/package/tasty.json),
[hedgehog](https://hackage.haskell.org/package/hedgehog.json), and
[tasty-hedgehog](https://hackage.haskell.org/package/tasty-hedgehog.json).
Upstream repositories: [text](https://github.com/haskell/text),
[tasty](https://github.com/UnkindPartition/tasty),
[hedgehog](https://github.com/hedgehogqa/haskell-hedgehog), and
[tasty-hedgehog](https://github.com/qfpl/tasty-hedgehog).

Hedgehog 1.5 deliberately matches the released version in the managed GHC 9.12.4
Nix package set. Its public property API is sufficient for this foundation. This
avoids a divergent Cabal/Nix dependency selection; it is not an unpublished
patch or an `allow-newer` exception. No compatibility workaround is required.
The requested Cabal snapshot is `2026-10-18T00:00:00Z`, verified reachable by
`cabal update`; the freeze file records the last actual index event before it,
`2026-10-17T17:19:18Z`.

API inspection used the Mori-indexed Tasty `Test.Tasty` and
`Test.Tasty.Hedgehog` source, Hedgehog's public `Hedgehog` module, and the
Jitsurei prelude guidance. The local source revisions inspected were
`2ef0bba406c24fcb6745515530ee5370934f329e` for the Tasty corpus,
`4ba91e4a16804885694e4b123a10613ac581194d` for the Hedgehog corpus, and
`f684a0be02a2ef65e0da21421e70dda60b5fc899` for the text corpus. Actual builds
consume released Hackage sources, never another checkout's working tree.

The foundation depends on `base` and `text`; its tests introduce Tasty/Hedgehog.
The scenario description milestone adds GHC's boot `containers` for reference and
capability sets. Its [release listing](https://hackage.haskell.org/package/containers.json)
was checked before selecting the boot version. Lens and generic-lens will be
added when code uses them; constructor pattern matching already follows the
record standard. Database, HTTP, event store, and Settei dependencies belong to
their later package introductions and need fresh release/compatibility checks.
