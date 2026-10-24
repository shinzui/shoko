# Describing, composing, and running scenarios

A context defines business operations as a `Vocabulary` GADT: each constructor
retains its operation's result type and describes its public ID, capabilities,
input dependencies, and substeps. `declareOperation`, `dependsOn input`, and
`withSubstep` build that description without reading input values. Compiling
consumers cover [accounts](../shoko-core/test/Consumer/Account.hs),
[durable deliveries](../shoko-core/test/Consumer/DeliveryLedger.hs), and
[composed registration/accounts](../shoko-core/test/Consumer/Composed.hs).

`given` and `act` return opaque `Ref a` values. `fromRef`, `pure`, `fmap`, and
applicative composition produce `Input a` values without resolving runtime
results. `accept [tags] operation` declares accepted domain outcomes, including
documented rejections. An observation checks a typed result with `observe` or
`observeThat`; `eventually`, `never`, and `exactlyOnce` add temporal meaning,
and `within` bounds an expectation group.

A reusable workflow is an ordinary `ScenarioBuilder op a`, optionally taking
inputs and returning references and correlation handles for its caller:

```haskell
registrationBlock :: ScenarioBuilder Registration (Ref Text, CorrelationRef)
registrationBlock = do
  qualified <- given "qualified" (accept ["ready"] Qualified)
  registered <- act "complete" (accept ["completed"] (Complete (fromRef qualified)))
  selected <- correlate (CorrelationAlias "registration")
    (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $ eventually "registered" $ correlatedBy selected $
    observeThat (Registered (fromRef registered)) (predicate "exists" id)
  pure (registered, selected)
```

`namespace "inviter" registrationBlock` qualifies local node, expectation, and
correlation instance IDs, for example `inviter.complete` and
`inviter.registration`. Nested namespaces join with dots. Returned references and
handles retain their fully qualified identity outside the block; external inputs
and handles keep their original identity inside it. Operation IDs, predicate IDs,
and semantic business-key names remain unchanged. Empty namespace components and
colliding qualified identifiers fail inspection. Correlation aliases have their
own namespace, separate from node/expectation IDs.

Strict `expect` forbids later actions. `expectAfterActions` lets a block declare
its consequences while allowing more actions to follow. Both run after the last
action, with one shared activation time. Deferred declarations are never
intermediate checkpoints. Their relative declaration order is preserved.

`predicate name test` gives a named predicate. Compose it with `.&&.`, `.||.`,
`negated`, or `onPart label project`; `observeThat` retains both the derived ID
and leaf validation metadata. Names use ASCII letters, digits, `_`, `-`, and `.`.
For example, `predicate "exists" id .&&. negated (predicate "absent" not)` renders
as `(exists and not(absent))`.

Combine context vocabularies with `(:+:)` and their bindings with
`combineBindings`. Result-preserving vocabulary maps lift existing concrete
producers without changing their definition:

```haskell
composedRegistration :: Scenario (Registration :+: Accounts)
composedRegistration =
  scenario "composed-registration" "Register two entities and check an account" "v1" $ do
    _ <- namespace "inviter" (hoistScenarioBuilder InL registrationBlock)
    (invitee, _) <- namespace "invitee" (hoistScenarioBuilder InL registrationBlock)
    hoistScenarioBuilder InR (accountBlock invitee)
```

The accounts block creates its own account ID, declares `account` with semantic
key `accountId`, and selects that handle on its observation. The returned
registration reference connects the two contexts. `hoistAction`,
`hoistObservation`, and `hoistExpectations` provide the same vocabulary mapping
at smaller boundaries. Each accepts `forall x. f x -> g x`, preserving result
types, predicates, windows, and correlation selections. Optional `Member`/`inject`
support distinct vocabularies in right-nested sums. Explicit `InL`/`InR` chooses
an occurrence in repeated vocabularies or other sum shapes. Conflicting operation
IDs with different capabilities or substeps fail inspection; dependencies may
vary across uses of one operation. Authors still choose stable context-qualified
operation IDs.

Finalize each independent verification with its own scenario ID and revision:

```haskell
registrationAlone = scenario "registration-alone" "Register one entity" "v1"
  (registrationBlock >> pure ())
registrationReused = scenario "registration-reused" "Reuse the workflow" "v1"
  (registrationBlock >> pure ())
```

To reuse an existing scenario, move its builder definition into a named workflow
and keep the original `scenario` call as a thin wrapper. There is no finalized
scenario concatenation or extraction API. Every wrapper owns its revision, which
must change when the shared predicates or recipe change. Runs acquire fresh
resources and produce separate reports.

Inspection and resolution are pure; execution uses the single bounded runner:

```haskell
inspectScenario :: Vocabulary op => Scenario op -> Either [DefinitionError] Description
resolveScenario :: Vocabulary op
  => Environment -> RunOptions -> Binding op resource -> Scenario op
  -> Either [PreflightError] (ResolvedScenario op resource)
runScenario :: Vocabulary op
  => Clock -> LogicalInput -> ResolvedScenario op resource -> IO RunResult
```

Import construction functions from `Shoko`, descriptions from `Shoko.Scenario`,
result constructors from `Shoko.Result`, clocks from `Shoko.Clock`, and wire
functions from `Shoko.Result.Json`. Resolution checks handlers, roles, source
consistency, all capability requirements, correlation compatibility, and synthetic
consent before acquisition. Production execution remains unsupported.

`binding name acquire release handlers` constructs an abstract binding. Its
lookup returns `Right Nothing` for unsupported operations, `Right (Just handler)`
for supported ones, or `Left HandlerBuildError` for invalid construction. Those
causes survive preflight as `HandlerConstructionFailed`; never collapse them into
absence. `actionHandler` serves fixture/action roles. `observationHandler` owns its
contract, `Source`, correlation requirement, and execution callback.
`noRequirements`, `requiring`, and `cleanupRequiring` construct contracts;
`requiringLifecycle` declares unconditional acquisition/release requirements.
Read-only accessors expose metadata without running IO.

`sampledSource (SourceId "accounts.state")` captures a host monotonic baseline.
`newSource` supplies custom capture and coverage for a durable reader. `focus`
projects both capture and execution into a larger resource. Reusing one source
label inside a binding asserts the same acquired reader and capture semantics;
equal coverage cannot establish closure identity. Distinct readers/scopes need
distinct labels. `combineBindings` acquires both components, unions lifecycle
requirements, and rejects cross-component source collisions before acquisition.
Completed leaves register their releases under masking and clean up in reverse
order under one shared grace deadline. Partial acquisitions register cleanup
before further interruptible work; each resource is released once.

Contexts are abstract. `resolveInput context input` returns
`IO (Either InputResolutionError a)`, distinguishing undeclared dependencies,
missing references, type mismatch, and detached contexts. Denied accesses remain
recorded even if a handler ignores `Left`; they cannot produce Pass.
`runSubstep context name action` only executes declared substeps under the
remaining request deadline. `requestDeadline`, `evidenceUntil`, `sourceBaseline`,
`correlation`, `executionId`, and `callClock` are plain accessors.
`detachedCallContext` supports direct adapter tests and refuses input resolution
and substeps. Bindings remain trusted Haskell responsible for accurate contracts.

`CorrelationAlias`, `BusinessKeyName`, `CorrelationId`, and `SourceId` are distinct
newtypes with explicit constructors and text accessors. They have no `IsString`
instances. `MonotonicTime` is an absolute microsecond timestamp; `Duration` is a
relative budget. Use `addDuration`, `differenceMicros`, and `monotonicMicros`
instead of numeric instances. The fake clock advances by `Duration`. These types
retain scalar string/integer JSON representations.

`correlate alias businessKey input` declares one correlation instance. Every
observation selects its instance with `correlatedBy`; an outer selection replaces
an inner one. A handler's `RequiresBusinessKey key` constrains compatibility and
does not select an instance implicitly. Missing, undeclared, and incompatible
selections are preflight errors. Two namespaced registrations may use the same
`registrationId` key with distinct values. Declarations depend only on earlier
nodes. After actions, an empty or unresolved value makes only that instance's
observations `Unknown/CorrelationLost`; terminal action failure suppresses every
expectation as `PrerequisiteUnavailable`. Native reads can use `guardCorrelation`
to compare the operation's typed key input with its selected business key.

`propagateExecutionId` declares one global `execution-id` handle. Repeated calls,
including in namespaces, are idempotent; the alias is reserved for this strategy.
Actions receive `executionId context == Just runId` only when it is declared.
Observations separately receive their explicitly selected correlation. HTTP
handler wrappers populate the run label, reject conflicting labels, and transmit
it only to opted-in endpoints. Declaring or transmitting a run ID does not prove
remote durable propagation; a context must establish that proof and use an ID
format compatible with its target.

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

`evidenceUntil context` is the fixed evidence cutoff; `requestDeadline context` is the
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

`encodeRunResult` and `decodeRunResult` own explicit v2 fields and tags. The decoder
checks the version, known fields/tags, typed values, and description digest; decode
errors omit input fragments. The digest is SHA-256 of a versioned fixed-order JSON
array of public description fields, with counts delimiting variable sequences.
It excludes runtime inputs; scenario revision, binary identity, and logical recipe
remain separate identities. The public
[schema](../schemas/run-result-v3.schema.json) and
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

Revision 2026-10-19: document composable builders, handler-owned sources, explicit
correlation instances, vocabulary hoisting, typed boundaries, and result v2.
