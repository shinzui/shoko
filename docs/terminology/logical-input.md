---
type: "Term"
title: "logical input"
description: "The recipe revision and allowlisted logical parameters that identify a run's test setup without storing raw fixture values."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-28"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-27"
  - "TERM-36"
  - "TERM-13"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Result.hs"
---

# logical input

The recipe revision and allowlisted logical parameters that identify a run's test setup without storing raw fixture values.

It can distinguish intended test conditions using public choices, counts, and flags. It is separate from private operation inputs and the scenario description digest. The runner validates recipe metadata before acquisition; hashing a secret raw fixture is not a substitute for choosing safe parameters.

See the [implementation or guide](../../shoko-core/src/Shoko/Result.hs).

Related: [input](input.md), [public summary](public-summary.md), [description digest](description-digest.md).
