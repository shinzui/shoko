# Describing and running a scenario

Core consumers define business operations as a GADT, a Haskell datatype whose
constructors retain each operation's result type. They implement `Vocabulary` to
describe public operation IDs, capabilities, reference dependencies, and any
composite substeps. The compiling examples are
[account provisioning](../shoko-core/test/Consumer/Account.hs) and
[an append-only delivery ledger](../shoko-core/test/Consumer/DeliveryLedger.hs).
The account scenario runs through both a set of accounts and a differently named
creation log, checking their actual stored state through the same observation.

`scenario id title revision` builds a fixed sequence with `given` and `act`, then
an `expect` group. Named steps return opaque `Ref a` values. `fromRef`, `pure`,
`fmap`, and applicative composition form `Input a` values without reading runtime
results. `accept [tags] operation` declares allowed domain outcomes, including a
specific rejection when testing negative behavior. Expectations use `observe
predicateId operation predicate`, wrapped in `eventually`, `never`, or
`exactlyOnce`; `within` adds an enclosing window. The revision changes when
predicates or recipes change.

The supported entry points, all available from `Shoko`, are:

```haskell
inspectScenario
  :: Vocabulary op => Scenario op -> Either [DefinitionError] Description

resolveScenario
  :: Vocabulary op
  => Environment -> RunOptions -> CorrelationPlan -> Binding op resource
  -> Scenario op
  -> Either [PreflightError] (ResolvedScenario op resource)

runScenario
  :: Vocabulary op
  => Clock -> LogicalInput -> ResolvedScenario op resource -> IO RunResult
```

Import result constructors from `Shoko.Result`, clocks from `Shoko.Clock`, and
wire functions from `Shoko.Result.Json`. Inspection and resolution perform no IO.
Resolution checks the entire declared operation set, binding metadata, lifecycle
and cleanup capabilities, correlation support, and per-run synthetic consent
before acquisition. Production execution is unsupported. A missing handler or
denied capability is a preflight error rather than a failed business assertion.
The logical recipe revision and parameter names are also validated before
acquisition; invalid metadata returns `PreflightFailure` without executing a run.

A `Binding op resource` supplies pure contracts for each operation and its
`FixtureOperation`, `ActionOperation`, or `ObservationOperation` role, plus effectful
acquisition, release, baseline, action, and observation handlers. Acquisition
receives a finalizer registrar. Register partial resources before subsequent
interruptible work; use normal masked allocation/registration patterns where
needed. A resource can retain the registrar for fixtures that allocate later.
Registered finalizers run in reverse registration order; the completed resource's
release runs first. Avoid registering a second deletion for the same resource.
`Retained` records a contracted disposition when deletion is not appropriate.

Handlers resolve inputs through `CallContext.resolveInput`, which checks declared
dependencies and uses checked `Dynamic` lookups. No unchecked cast is used.
Composite actions call `CallContext.substep` with a declared substep ID; its
request shares the remaining deadline and produces timing/reason evidence.
Unknown substeps never execute. Bindings remain ordinary trusted Haskell code
responsible for describing their complete operation inventory.

`BusinessKeyFrom` can use a fixed non-secret input, while
`businessKeyFromResult key nodeId` selects a named action's `Text` identity after
that action completes. The latter is useful when a composite registration action
returns its registration ID. Missing node IDs fail preflight. A missing runtime
key yields `Unknown/CorrelationLost` without an uncorrelated observation.
Execution-ID correlation requires explicit binding support; merely assigning a
report run ID does not establish remote propagation.

The execution budget starts before acquisition and source baselines. Defaults
are 30 seconds total, 10 seconds for `eventually`, 100 milliseconds between polls,
and a separate five-second cleanup grace. `milliseconds` constructs positive
validated durations. Deadlines use monotonic microseconds; UTC timestamps label
reports. Sibling expectations share one activation time and run concurrently.
Nested windows take the minimum deadline. Every handler and composite substep is
bounded; mutating actions are never automatically retried after a timeout.
Handlers preserve asynchronous cancellation and classify expected transport
failures with `ActionUnavailable` or `ObservationUnavailable`. Unexpected handler
faults produce `RunnerFault` with sanitized reasons and available partial results.

Each evidence source captures a baseline before any fixture or action. Event
readers retain a source cursor as well as its host clock capture time. When an
action later supplies the business key, the reader queries from that already
captured baseline. Occurrence IDs must be stable and unique within the source
query; include the stream identity when positions are only stream-local.

`eventually` accepts a witness completed at or before its deadline. Healthy
conclusive non-matching scheduled reads permit Fail at expiry; unresolved gaps
produce Unknown. This is a sampled state guarantee unless the source establishes
durable history. `never` needs complete coverage of its bounded evidence interval
to pass and fails on a witness. `exactlyOnce` deduplicates occurrence IDs, fails on
a second distinct occurrence, and waits for complete interval closure before
passing with one or failing with zero. Snapshot rows cannot establish continuous
absence or durable occurrence cardinality. Complete history catch-up can repair
a previous source gap; a later mutable snapshot cannot repair it.
For an advertised durable source, `eventually` must also obtain complete closing
history before declaring a miss Fail. Its closing request may use remaining
execution time after the evidence cutoff; a positive completed after that cutoff
cannot Pass. A missing closing proof remains Unknown.

`CallContext.evidenceUntil` is the fixed evidence cutoff; `deadline` is the
remaining request bound. A negative/history check may need its final read after
the cutoff while execution budget remains. Use a shorter `within` window when a
real reader needs this closing read. That read cannot extend the evidence window
or execution budget. A source must actually establish the requested interval,
including cursor/transaction visibility and any time-to-source-bound mapping;
it cannot claim future coverage or silently include later occurrences. Without
that proof the result is Unknown. A negative window that consumes the whole run
budget may therefore lack sufficient time for closure. Cleanup grace is never
used to collect additional evidence.

Observed domain values remain private typed values. `ActionObservedWithDetails`
and `ObservedWithDetails` attach explicit public `PublicChoice`, `PublicCount`, or
`PublicFlag` summaries, such as a protocol status, row count, or state predicate.
Binders select these fields deliberately; they never forward response bodies,
passwords, OTPs, credentials, or personal payloads into summaries or outcome tags.
`LogicalInput` separately identifies the recipe and allowlisted logical parameters.
No raw fixture value is rendered or hashed as a substitute for redaction.

Reports preserve every child verdict and action outcome. Fail dominates Unknown,
which dominates Pass. Unexpected or uncertain actions stop later mutations and
mark dependent expectations unavailable. An allowed domain rejection remains a
value, so its rejection and downstream invariants can pass. Required cleanup
failure makes an otherwise passing result Unknown and preserves an existing Fail.
Real cancellation attempts finalization within the same finite grace and then
remains cancellation.

`encodeRunResult` and `decodeRunResult` own explicit v1 fields and tags. The decoder
checks the version, known fields/tags, typed values, and description digest; decode
errors omit input fragments. The digest is SHA-256 of a versioned fixed-order JSON
array of public description fields, with counts delimiting variable sequences.
It excludes runtime inputs; scenario revision, binary identity, and logical recipe
remain separate identities. The public
[schema](../schemas/run-result-v2.schema.json) and
[goldens](../shoko-core/test/golden/) cover verification, expected rejection,
Fail, Unknown, runner fault, and preflight error. They are unit examples rather
than staging acceptance.

Run `nix develop --command just check` for consumer/property/cancellation tests,
independent schema validation, formatting, and the Nix package build. To update
goldens deliberately after a contract change, build first and then run:

```bash
nix develop --command cabal build all
nix develop --command cabal exec -- runghc -XGHC2024 -XOverloadedStrings \
  -package=shoko-core -ishoko-core/test shoko-core/test/UpdateGoldens.hs
git diff -- shoko-core/test/golden/
```
