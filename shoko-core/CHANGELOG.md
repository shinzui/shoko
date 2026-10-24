# 0.3.0.0

Add source-free `holds` and `agreeOn` expectations with bounded one-shot evaluation,
private typed inputs, and truthful nullable completion evidence. Declare independent
actions with `concurrently`; bindings explicitly promise safe concurrent calls with
`allowConcurrentCalls`. Admitted siblings settle after ordinary failures, evidence
retains declaration order, and cancellation joins members before cleanup.

Breaking: expectation descriptions use observation/result subjects, expectation
evidence is tagged, nodes and steps carry group membership, and results use schema
v3 with a v3 description digest. The decoder accepts v3 only. First-party consumers
now require core >=0.3 && <0.4. The independent CLI host demonstrates sequential
retries and concurrent duplicate submissions with atomic and faulty controls.

# 0.2.0.0

Reusable namespaced workflow blocks and deferred consequences, composable named
predicates, and handler-owned binding contracts and sources. Identifiers and
absolute monotonic times have distinct types. Input resolution is effectful and
records undeclared accesses. Vocabulary sums, result-preserving hoisting, and
resource-safe binding composition connect independent contexts. Scenarios own
explicit correlation handles, including repeated business-key instances and
optional execution-ID propagation. Run results use schema v2 with per-instance
resolution and a v2 description digest.

# 0.1.0.0

Introduce typed, inspectable scenarios, capability and correlation preflight,
bounded three-valued execution, resource finalization, and explicit v1 evidence
reports. Include independent consumer implementations, temporal/property tests,
and a reproducible Cabal/Nix build.
