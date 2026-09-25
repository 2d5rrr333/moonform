# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2026-09-25

### Performance

Hot-path tuning for the derived-state checks every bridge snapshot runs
on each notification (behavior-preserving; the full suite guards the
semantics):

- `Key::has_prefix` no longer allocates (it used to build the stripped
  tail through `strip_prefix` just to answer a Boolean) — this runs on
  every value change for group dispatch and prefix-subscription matching
- `ErrorMap::has_errors` early-exits per slot instead of flattening the
  whole error list
- form-level `is_touched` / `is_blurred` / `is_dirty` /
  `is_valid_fields` / `is_validating_any` / `can_submit` return on first
  hit instead of scanning every entry
- group-level `is_touched` / `is_fields_valid` / `can_submit` are
  single-pass over the meta store (no sorted `keys_under` materialization)
- `can_submit` short-circuits the untouched-and-clean path before the
  full validity scan

### Added

- `examples/bench`: timed smoke over a 500-field array form (mount,
  validated writes, derived sweeps, group checks, remove-triggered
  migration) with correctness assertions — wired into CI. Measured on js:
  ~9ms mount, ~12ms for 500 validated writes, ~23ms for 100 full
  derived-state sweeps, ~2ms for the remove(0) meta migration
- Core scale smoke tests: error migration across 200 array slots,
  submission over 200 mounted fields, prefix-subscription fan-out under
  batch

### Tests

- 292 tests on js, 275 on wasm

## [0.7.0] - 2026-09-25

### Added

- **`examples/isomorphic`**: the isomorphic-validation scenario as a
  runnable artifact — ONE shared set of field validators (rules-based,
  zero deps) consumed by BOTH sides of the wire:
  - `examples/isomorphic` (library): the shared definitions + the
    server-side gate (`server_review` replays the validators through a
    fresh form instance)
  - `examples/isomorphic-client` (js executable): real-time per-field
    feedback while typing, clearing on fix, submit accepted
  - `examples/isomorphic-server` (native executable): the final gate —
    a hostile payload (UI bypassed) rejected on every field, a corrected
    payload accepted, partial invalidity reported per field
  - CI runs the client on js and the server on native; the library's
    blackbox tests run on all three targets (the isomorphism claim
    itself is asserted cross-target)
- upstream/SOURCES.md: replaced a dangling out-of-repo openspec path
  with the in-repo PARITY.md reference

### Tests

- 289 tests on js, 272 on wasm (3 isomorphic blackbox tests)

## [0.6.0] - 2026-09-25

### Added

- **`lens-gen` CLI** (`src/lens-gen-cli`, js target): .mbti file in, lens
  accessor source out —
  `moon run src/lens-gen-cli -- <pkg.mbti> [-o <out.mbt>] [core_alias]`.
  Reads the package interface produced by `moon info`, emits accessors for
  every concrete struct, writes exact bytes with `-o` (or prints for
  inspection). The emitter's output is now `moon fmt`-stable (doc-marker
  and trailing-comma aligned), so regenerated files pass format checks
  unchanged
- **`examples/generated`**: the generator's end-to-end proof — a library
  package whose lens accessors are checked in AS PRODUCED BY THE CLI
  (`profile_lenses.generated.mbt`), consumed by a real form flow
  (`run_demo`: validation errors per field, fix, submit — asserted by a
  blackbox test). CI regenerates the file from the package's .mbti and
  diffs it (freshness guard), so the generated artifact can never drift
  from the generator
- **`schema` doc-tests** (`README.mbt.md`): the schema group validator
  flow as executable documentation (distribution by JSON-Pointer paths,
  clearing on fix)

### Tests

- 286 tests on js, 269 on wasm

## [0.5.0] - 2026-09-25

### Added

- **`react`: `FormBridge` + `use_form`** — the whole-form counterpart of
  FieldBridge/GroupBridge, completing the bridge trio: a stable form-level
  snapshot (is_submitting / is_submitted / is_submit_successful,
  is_validating, is_valid_fields, can_submit, is_touched / is_blurred,
  submission_attempts, form-level submit_error) refreshed by a whole-form
  subscription; `bridge.submit` wires the submit button
- **`react`: `real_clock()`** — the js host adapter for the core Clock
  protocol (real timers behind the same injectable protocol the
  VirtualClock drives deterministically in tests; deviation D-P7's host
  story, now shipped). Core gains `Clock::make` as the host-adapter entry
  point
- **`core`: nested-group dispatch coverage** — a change deep inside
  nested groups dispatches every containing group (each runs its onChange
  listener and change validation; the form-level onChangeGroup listener
  fires once per containing group); regression test added
- **Browser wizard demo: asynchronous final submit** — the whole-form
  submission runs through the real-clock host adapter; the Finish button
  enters a disabled "Submitting..." in-flight state driven by the
  FormBridge snapshot, completing after 600ms. Headless verification
  grows from 14 to **15 checks** (login 5 + wizard 10)

### Tests

- 284 tests on js (5 FormBridge contract tests, 1 real_clock surface
  test, 1 nested-groups test), 267 on wasm

## [0.4.0] - 2026-09-25

### Added

- **`schema`: `schema_group_validator`** — a compiled moonschema schema as a
  group validator: validates the group value, distributes errors to child
  fields by their JSON-Pointer paths relative to the group root
  ("/username" → the group's username field, "/friends/0/name" → the nested
  element key); root-path `required` errors distribute to the named
  property, other root-path errors (e.g. `minItems` on an array group)
  become group-level errors. JSON-Pointer parsing handles array indices and
  escape-free tokens; covered by blackbox behavior tests (struct groups,
  array groups, nested element fields) and whitebox unit tests
- **`core`: `GroupValidationResult::make`** — general construction
  (group errors + per-field message lists) for aggregating adapters
- **Browser wizard demo** (`web/wizard.html`, `src/web-demo-wizard`):
  multi-step group form end-to-end — step 1 validates through a moonschema
  schema group validator (distributed field errors visible per input),
  step 2 through a manual dual-channel validator (group-level + field
  error); group submission gates each step, the final step submits the
  whole form. Headless verification grows from 5 to **14 checks** (login 5
  + wizard 9) in `tools/headless-verify.cjs`

### Fixed

- **Group onMount errors never cleared**: a group's own onMount error now
  clears when a value inside the group changes (child write or whole-group
  write), mirroring field-level `set_value` clearing Mount errors —
  previously a stale onMount group error could never clear. Regression
  tests included (surfaced by the schema group validator's array-group
  test)

## [0.3.1] - 2026-09-25

### Changed

- **Toolchain migration to MoonBit 0.1.20260920** (moonc 0.10.14): the new
  `implicit_impl_as_method` deprecation requires explicit `pub extend T with
  Trait::{...}` declarations for every derive/explicit impl. Added across
  all packages (136 declarations), including a mechanical migration patch
  to the vendored moonschema source (documented in
  `src/vendor/moonschema/NOTICE.md` — no behavioral change)
- Blackbox test files qualify own-package references (`@rules.required()`
  etc.) per the `test_unqualified_package` deprecation; doc-tests in
  `core/README.mbt.md` qualify `@core.` references and declare extends for
  their local structs; lens-gen's test suite moved from blackbox to
  whitebox (hyphenated package names have no usable self-alias)
- Browser demo artifact (`web/main.js`) rebuilt on the new toolchain;
  headless verification 5/5

### Verified

- `moon check --target js/wasm/native --deny-warn` zero warnings;
  `moon test --deny-warn` 269 (js) / 258 (wasm); `moon fmt --check`;
  interface files regenerated (`moon info` — extends surface as public
  methods in `pkg.generated.mbti`)

## [0.3.0] - 2026-09-25

### Added

- **`react`: `GroupBridge` + `use_group`** — the group counterpart of
  FieldBridge/use_field: a stable per-group snapshot (value, group errors,
  is_fields_valid/is_group_valid/is_valid, can_submit, is_validating,
  group-scoped submission_attempts) refreshed by a **prefix subscription**
  so any child-field change (distributed errors, touched flags) updates the
  group view; `bridge.submit` wires the group's submit button without
  touching the parent form's submit state
- **`core`: prefix subscriptions** — `FormApi::subscribe_under(key, kinds?)`
  fires on the key itself and every key under it (whole-segment prefix
  match); the natural subscription for group/subtree adapters
- **`examples/wizard`**: multi-step form — per-step group validation with
  both error channels at once (group-level + distributed), group
  submissions that never touch the form's submit state or sibling groups,
  and a final whole-form submit gated on every step being valid; wired
  into CI
- CI hardening: `moon check --deny-warn` on all three targets,
  `moon test --deny-warn`, `moon fmt --check`, and an interface drift
  guard (`moon info` + `git diff --exit-code` on `*.mbti` — the rules
  package interface had drifted silently before)

### Tests

- 269 tests on js (react package gains 7 GroupBridge contract tests;
  core gains 4 prefix-subscription tests), 258 on wasm; native check
  clean, native tests run in CI

## [0.2.0] - 2026-09-25

### Added

- **`FormGroupApi`** (core): group-scoped validation and submission over a
  lens prefix (upstream form-core@1.33.5 FormGroupApi):
  - Group validator protocol (`GroupValidator` / `AsyncGroupValidator`) with
    structured `GroupValidationResult`: group-level errors plus field errors
    distributed to child fields — including fields that are not mounted yet
    (their errors surface on mount)
  - Group submission (`handle_submit`) that never touches the parent form's
    submit state (onSubmit handler, submissionAttempts, isSubmitting);
    field errors short-circuit the group's own onSubmit validation; submit
    `meta` flows through to the callback
  - Derived group state: `errors` / `error_for_cause`, `is_fields_valid` /
    `is_group_valid` / `is_valid`, `can_submit`, group-scoped
    `submission_attempts`, `is_validating`; async onChange validation with
    debounce and race-abort on unmount
  - Group listeners (onMount/onChange/onUnmount receive the group value)
- **Form-level change listeners** (upstream form `listeners.onChange` /
  `onChangeGroup`): `FormApi::make(on_change=…, on_change_group=…)` with
  independent debounce windows driven by the form's Clock
- **`FieldApi::reset`** (upstream `resetField`): value back to the effective
  default, meta reset to default
- `moon info` interface files regenerated (rules .mbti had drifted stale)

### Tests

- Upstream parity grows from 143 to **185 translated tests**: 26 from
  FormGroupApi.spec.ts, 16 FieldGroupApi.spec.ts cases as lens-composition
  equivalence tests (the string-remapping machine is subsumed by accessor
  composition — deviation D-P8); exemptions and deviations re-ledgered in
  upstream/PARITY.md
- 259 tests on js, 254 on wasm, native check clean; three-target
  `moon check --deny-warn` zero warnings

## [0.1.1] - 2026-09-19

### Fixed

- **Stale-index safety for array operations**: after remove/insert/swap,
  mounted per-element fields whose index no longer exists crashed
  change-validation dispatch with an uncatchable `Array::at` abort (js).
  `Lens` gains `try_get` (Option semantics; `at`/`compose` propagate
  staleness); change/submit validators, change listeners, dirty probes,
  mount and async validation all read through `try_get` and skip stale
  slots. Regression tests included.
- **React adapter notify contract**: `FieldBridge` now calls React's
  re-render callback on every core notification (`attach_with_notify`;
  `FieldBridgeHook::subscribe(notify)` matches the external-store
  contract). Without it, controlled inputs silently reverted to stale
  snapshots. Verified end-to-end in a real browser (headless Edge,
  5/5 checks: render, error display, error clearing, submit).

### Added

- `rules`: `email` / `url` pragmatic format rules, `min_int` / `max_int`,
  `equals`, `must_be_true`, `non_blank`, `numeric`
- `examples/roster`: dynamic array form demonstrating error migration
  across remove/push/swap with submit gating (wired into CI)
- `web/`: browser login demo (tiye/react + React 18.3.1 UMD vendor,
  self-test harness, headless verification tooling)
- `ValidationCause` public constructors (mount/change/blur/submit/server)
  for blackbox callers
- README installation section, English README, CHANGELOG; upstream/
  carries the TanStack Form MIT license text
- CI: GitHub Actions — check (js/wasm/native) + test (js/wasm/native)
  + examples + browser self-test

## [0.1.0] - 2026-09-19

Initial release. Behavior semantics baseline: TanStack form-core@1.33.5
(upstream test suite translated to MoonBit; see `upstream/PARITY.md`).

### Added

- **core** (zero third-party dependencies, js/wasm/native):
  - `FormApi`/`FieldApi` state machine: default values/state, field
    read/write, touched/blurred/dirty derivation, `reset` (field-level
    default priority, `keep_default_values`, new-defaults semantics), `update`
  - Structured keys (`Key`, segment list) with prefix matching and
    array-operation remapping as pure functions
  - Lens accessors (`(key, get, set)` triples) with composition; replaces
    dot-path strings — compile-time safe, rename-safe
  - `MetaStore`: per-field metadata keyed structurally (touched/blurred/
    validating/dirty, per-cause error slots, `array_version`)
  - Array field operations: push/insert/remove/swap/move/replace/clear with
    meta migration (nested arrays included); out-of-range and no-op edge
    semantics follow upstream
  - Subscriptions with stable handles, change-kind filtering, and batched
    notification coalescing; field listeners (onChange/onBlur/onMount/
    onUnmount/onFieldUnmount); field mount/unmount semantics (interaction
    flags preserved, stale-instance guard, `delete_field`)
  - Validator protocol (sync per cause: Mount/Change/Blur/Submit/Server);
    async validators with debounce windows and race-abort guards; virtual
    `Clock` protocol + `VirtualClock` test driver
  - Cross-field linkage (`listen_to`, upstream onChangeListenTo) and
    dynamic conditional validation
  - Submit orchestration: preventDefault (count revert), validation gates,
    `on_submit_invalid`, `is_submitting` lifecycle, async completion via
    Clock, `can_submit`, form-level submit errors
- **rules**: required/required_array, min/max length, min/max value,
  contains/starts_with, custom closures; chained combination
- **schema**: moonschema adapter — per-field validators over a compiled
  JSON-Schema via JSON-Pointer error paths (required-parent-path
  special-cased); moonschema@0.1.0 vendored (Apache-2.0)
- **react**: `FieldBridge` (Object.is-stable snapshots) and `use_field`
  over tiye/react `use_sync_external_store` (js target)
- **lens-gen**: .mbti parser + lens emitter (idempotent, rename-safe,
  same API shape as hand-written accessors)
- **examples/login**: email/password login form (moonschema validation,
  submit flow), headless-verified
- **upstream/**: form-core@1.33.5 test sources (MIT, attribution in
  SOURCES.md) + PARITY.md ledger: 143 translated tests, exemption and
  deviation lists

### Tests

- 198 tests on js, 193 on wasm, native check clean; three-target CI

### Published

- `2d5rrr333/moonform@0.1.0` on mooncakes.io
