-- OKF profile descriptor written by `okf profile init`.
-- 
-- Profile: coordination.improvementRequests
-- Source:  https://raw.githubusercontent.com/shinzui/okf-profiles/v0.22.0/package.dhall
-- 
-- Existing hashes are preserved and unhashed remote value imports are frozen.
-- Local and environment inputs remain live; this is not a portable snapshot.
-- To update remote imports, remove their hashes and run `dhall freeze profile.dhall`.
-- Never hand-write a sha256 value.
let registry =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.22.0/package.dhall
        sha256:2294a5bd32ca22daa89610e12fde81dd3115701fcb0bf7a790c7bdee6d85db65

in  registry.coordination.improvementRequests
