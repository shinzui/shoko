# Bundle Update Log

## 2026-10-23
* **Addition**: Add CAP-12 for bounded API-backed email evidence and controlled input sending, with compiled loopback consumers and offline smoke-host checks.

## 2026-10-21
* **Update**: Extend CAP-9 and CAP-10 with generic workflow v2 validation and the shared bounded read-only target-observation gate; preserve v1 registration compatibility.
* **Addition**: Add strict catalog inspection and explicit compiled-host dispatch with real consumer process evidence.
* **Event readers**: Refresh CAP-7 for typed rejection of Kafka topic scopes and record correlation by the SQL readers. The Kafka topic reader is not catalogued until hosts can allocate it.

## 2026-10-19
* **Composition API**: Refresh CAP-1, CAP-6, and CAP-8 for reusable blocks, explicit correlation selection, per-operation handlers, execution labels, and result v2; add the compiled registration composition as evidence.
* **Catalog**: Document CAP-1 through CAP-10 with current interfaces, repository evidence, experimental stability, and explicit limits.
* **Adoption**: Adopt [the capabilities profile](mori://shinzui/okf-profiles/profiles/capabilities), export `coordination.capabilities`, at frozen v0.21.0.
