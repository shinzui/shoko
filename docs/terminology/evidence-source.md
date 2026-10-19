---
type: "Term"
title: "evidence source"
description: "A named read surface from which a binding obtains observations for a finite run."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-21"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-3"
  - "TERM-12"
  - "TERM-4"
anchors:
  - kind: "doc"
    resource: "docs/adapters.md"
---

# evidence source

A named read surface from which a binding obtains observations for a finite run.

A public source identity denotes the selected scope and decoder, independently of connection credentials. The runner captures its baseline before fixtures and actions. An event reader needs a distinct identity for each scope/decoder; the source name alone does not establish complete history.

See the [implementation or guide](../../docs/adapters.md).

Related: [baseline](baseline.md), [coverage](coverage.md), [binding](binding.md).
