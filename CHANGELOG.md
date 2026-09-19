# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
