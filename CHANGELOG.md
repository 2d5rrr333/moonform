# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
