---
type: "Term"
title: "description digest"
description: "The SHA-256 identity of a versioned encoding of a scenario's public description."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-13"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-44"
  - "TERM-28"
  - "TERM-19"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Result/Json.hs"
---

# description digest

The SHA-256 identity of a versioned encoding of a scenario's public description.

The encoding uses fixed-order fields and sequence counts, and excludes runtime inputs. The result decoder checks this digest against the embedded description. It identifies the public structure; it cannot prove that opaque Haskell predicate implementations are unchanged.

See the [implementation or guide](../../shoko-core/src/Shoko/Result/Json.hs).

Related: [scenario revision](scenario-revision.md), [logical input](logical-input.md), [evidence](evidence.md).
