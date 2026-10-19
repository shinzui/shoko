-- OKF profile descriptor written by `okf profile init`.
--
-- Profile: mori://shinzui/okf-profiles/profiles/terminology
-- Export: documentation.terminology at v0.21.0
--
-- Existing hashes are preserved and unhashed remote value imports are frozen.
-- Local and environment inputs remain live; this is not a portable snapshot.
-- To update remote imports, remove their hashes and run `dhall freeze profile.dhall`.
-- Never hand-write a sha256 value.
let registry =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.21.0/package.dhall
        sha256:4be32588d55c74282ceab54b06b22f552cdbf4215788e3eb5256ee8744cb92a2

in  registry.documentation.terminology
