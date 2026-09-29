# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.3] - 2026-09-29

### Added

- **Async randomized fuzz** — the TIME dimension joins the structural
  fuzz: a deterministic PRNG drives 6,300 interleaved steps (21 seeds ×
  300) of writes (three verdict classes) × blurs × overlapping async
  submissions × resets × random clock ticks (0/5/15/60/200ms — debounce
  windows, completions, and full drains in the mix). Invariants:
  `is_validating` never sticks once the clock drains; the drained error
  state reflects exactly the last write's async verdict (debounce
  coalescing — a mid-flight sync "required" is correctly REPLACED by the
  async result per single-slot cause semantics); a reset discards every
  in-flight completion (no `is_submitted`/`is_submitting`/error
  residue); submission attempts stay monotone and non-negative; only
  the latest submission's completion applies (identity guard)
- **Structural fuzz seed soak**: the array/mount/subscription fuzz adds
  a 32-seed sweep (12,800 steps per run) on top of its fixed seeds

### Tests

- 380 tests on js, 348 on wasm (+1 test, two fuzz families inside)

## [0.9.2] - 2026-09-29

### Fixed

- **`clear_values` orphaned Mount-cause distributed errors** (fuzz-found,
  the permanently-blocks-submission class): clearing left every old
  slot's meta in place, and a Change re-validation only clears its own
  cause's owned records — so errors a group distributed on MOUNT
  survived on the stale slot keys forever (`is_fields_valid` stayed
  false; the group could never submit again). Clear now vacates every
  old slot — meta and registration deleted, subtree notified — mirroring
  remove_value's treatment of its vacated last slot (clear is remove for
  every position)

### Added

- **Randomized stress fuzz** (the audits' standing blind spot — several
  fixed bugs depended on exact map layouts that small deterministic
  cases pass over): a deterministic PRNG drives 2,400 interleaved steps
  (6 seeds × 400) of array operations × field mount/unmount (including
  stale indices) × subscription churn × group error distribution, with
  invariants asserted after EVERY step — values match a shadow model of
  the documented clamp/no-op semantics; no negative index ever appears
  in a meta key; distribution is exact on live slots and absent on stale
  slots and while the group is unmounted; unsubscribed subscribers never
  fire. The clear_values orphan above is its first catch

### Tests

- 379 tests on js, 347 on wasm (+2: the fuzz itself and a deterministic
  clear_values orphan regression)

## [0.9.1] - 2026-09-29

### Fixed

The fourth audit round — the lens generator, `delete_field`, and the
vendored schema engine's adversarial-input surface:

- **lens-gen: `} derive(...)` closing lines ended nothing** (severe): the
  struct parser only recognized a bare `}` — every struct with a derive
  clause (i.e. every struct `moon info` emits for derive(Eq) types) ran
  past its end and absorbed the NEXT struct's fields, duplicating
  accessors and dropping structs outright (reproducible on this repo's
  own .mbti files). Any brace-leading line ends the struct now
- **lens-gen: `pub(all)` structs silently skipped**: form value types
  commonly use `pub(all)` for external construction — the header matcher
  now accepts every pub visibility (`pub` / `pub(all)` / `pub(readonly)`)
- **lens-gen: `mut` fields silently dropped**: the modifier is stripped —
  mut fields get accessors like any other field
- **lens-gen: accessor-name collisions generated uncompilable code**
  (`FooBar.x` and `Foo.bar_x` both yield `foo_bar_x_l`): colliding fields
  are skipped with a marker comment instead
- **lens-gen CLI**: `-o` as the last token silently became the core
  alias (garbage output, exit 0); unknown flags overwrote it likewise;
  a missing input file died on a raw Node stack. Arguments are validated
  (flags position-independent, `-o` requires a value, at most one alias),
  unknown flags and missing files print a clear error with usage
- **`delete_field` never notified the removed subtree**: only the
  deleted key itself notified — exact-key subscribers on deeper keys
  (e.g. `items.1.name` under a deleted `items.1`) stayed stale forever.
  Every removed key now notifies (batched)
- **vendored moonschema: `$ref` cycles and deeply nested schemas crashed
  with a stack overflow** (`{"$ref": "#"}`, mutually-referencing defs,
  600-deep documents): a shared depth counter caps compile and validate
  recursion at 256 levels (compile raises `InvalidSchema`; validation
  records an error) — NOTICE.md discloses
- **vendored moonschema: percent-escaped non-ASCII `$ref` pointers never
  resolved** (`#/properties/%E4%B8%AD%E6%96%87` decoded each UTF-8 byte
  as Latin-1 mojibake, so Chinese property keys could not be
  referenced): escapes now decode as UTF-8, invalid sequences kept
  verbatim
- **vendored moonschema**: the x-rules lexer extracted number/identifier
  tokens by codepoint indices into UTF-16 slices — any emoji earlier in
  the expression garbled every later token; count keywords
  (`minLength` etc.) accepted up to 9e15 and silently saturated to
  Int32 on conversion (now an explicit compile error past the Int
  range); the `enum` error message claimed "non-empty" while empty
  arrays were accepted

### Added

- The generated-accessors example now carries TWO structs (one
  `pub(all)`, both with derive closing lines) — the CI
  regenerate-and-diff self-check pins the authentic `moon info` shapes
  the parser previously mishandled

### Tests

- 377 tests on js, 345 on wasm (+10: derive/pub(all)/mut/collision
  parsing, delete_field subtree notification, $ref cycles, deep-schema
  compile cap, UTF-8 pointer decoding, Int-range counts, emoji-token
  lexing)

## [0.9.0] - 2026-09-29

### Fixed

The third audit round — the adapter layer (react bridges, schema
adapter, rules) had none of the core's 0.8.5 staleness guards:

- **FieldBridge/GroupBridge snapshots aborted on stale array slots**
  (crash): snapshot builders read through `lens.get`/`group.value()` —
  after `remove_value` shrank the array, the structural notification
  refreshed the bridge straight into an index-out-of-range abort. Both
  read through `try_get`/the new `FormGroupApi::try_value` and keep the
  last live value on a stale slot (the structural-change contract has
  adapters re-mount per slot)
- **Element-addressed bridges never refreshed on structural changes**:
  swap/move/remove/insert shift a DIFFERENT slot's data onto a bridge's
  position without writing its key — snapshots stayed silently stale.
  Array operations now batch-notify every per-slot key under the array
  (one callback per subscriber), mirroring upstream's per-field meta
  touch
- **The hooks' subscribe closures were unstable across renders**
  (React contract): `use_field`/`use_group`/`use_form` built a fresh
  closure every render, re-subscribing each commit and opening detach
  windows where cross-component writes were missed entirely (stale UI
  until the next core change). The hook structs now carry an
  identity-stable `subscribe_fn`; the web demos use it directly
- **Re-attached bridges served stale snapshots**: attach subscribed but
  never rebuilt, so a bridge surviving detach (StrictMode remounts,
  ref-held bridges) rendered pre-detach state after re-attaching. All
  three bridges rebuild on attach (no notify — no re-render storm)
- **`FormState.is_validating` never lit up**: it read the default-state
  overlay, which no validator writes. It now reads the new public
  `FormApi::is_validating_any` (field meta + in-flight group asyncs)
- **`FieldState.is_dirty` was a sticky flag, not derived**: writing a
  value and manually reverting it left dirty=true forever (upstream
  derives isDirty by value comparison). The snapshot now derives it
  (FieldBridge gains an `A : Eq` bound — the documented
  derive(Eq)-your-values contract)
- **Group unmount never notified the group's key**: prefix subscribers
  (GroupBridge) kept the pre-unmount group errors in their snapshots.
  Unmount now notifies the group key after clearing its state
- **Async submit completions landed on superseded submissions**: a reset
  mid-flight resurrected success/error state on the reset form (and a
  stale `Prevented` decremented the reset counter below zero); a newer
  submission's completion could be overwritten by the older one's late
  finish. Submissions now carry an identity (a monotonic seq bumped by
  every submit and by reset); only the active submission's completion
  applies
- **real_clock `now` overflowed Int** (Date.now() ms ≈ 2^40 truncated):
  now returns wall-clock seconds (fits Int until 2038; diagnostics
  only — the core never reads it). **setTimeout ids**: Node/Bun return
  Timeout OBJECTS, violating the Int return slot — schedule now hands
  out its own increasing numeric ids behind a registry (browsers and
  Node identical)
- **schema adapter: JSON-Pointer escapes ignored**: `~0`/`~1` were
  never unescaped (property names containing `~`/`/` never received
  their errors; the field matcher compared raw names against escaped
  paths — both sides now escape/unescape per RFC 6901). All-digit
  segments with leading zeros ("01") or 9+ digits (phone-number keys)
  wrapped/overflowed into bogus array indices — only canonical indices
  (no leading zero, ≤ 9 digits) map to `Idx` now, mirroring moonschema's
  own pointer parser. `quoted_property` sliced by UTF-16 offsets against
  codepoint indices (emoji property names garbled) — rebuilt from the
  codepoint array
- **vendored moonschema format asserts aborted on supplementary-plane
  characters**: `is_email`/`is_uuid` mixed `String::length()` (UTF-16
  units) with `to_array()` indexing (codepoints) — pasting an emoji
  into an `assert_format` email/uuid field aborted. Unified to codepoint
  iteration; NOTICE.md updated (vendored-file disclosure)
- **rules**: `numeric("-")` accepted a bare sign (at least one digit
  required now); `min_length`/`max_length` counted UTF-16 units while
  the schema engine counts codepoints (an emoji now counts as one
  character, consistent with minLength semantics and the extreme-input
  tests' documented contract); `non_blank` now treats U+00A0, U+3000
  (CJK ideographic space) and \x0B/\x0C as blank; email doc aligned
  with the code (TLD ≥ 2)

### Tests

- 367 tests on js, 335 on wasm (+17: bridge × array ops, derived dirty,
  live validating, attach_with_notify, group-unmount refresh, submit
  identity guards, pointer escapes/indices, format emoji regression,
  rules unicode/numeric edges)

## [0.8.6] - 2026-09-29

### Fixed

Closing out the 0.8.5 audit's secondary findings:

- **In-flight async GROUP validation did not gate form submission** (the
  field/group asymmetry): `can_submit` only saw field-level
  `is_validating` meta. The form now carries an in-flight group-async
  counter (maintained by `FormGroupApi::set_validating`, aborted on
  unmount/reset), and `is_validating_any` consults it — matching
  upstream's single form-level isValidating across every async validator
- **A remounted group inherited its previous life's state**:
  `submission_attempts` and `is_touched` survived mount→unmount→mount on
  the same handle, skewing `can_submit`'s never-touched branch. A mount
  is now a fresh lifecycle (upstream: every mount creates a new
  FormGroupApi)

### Added

- Subscription blind-spot tests (the 0.8.5 audit's coverage list):
  mid-notify unsubscribes on the `notify_all` path (reset); mid-flush
  unsubscribes in `batch`; mixed `notify` + `notify_all` batch pending
  (one fire per subscriber); writes inside a flush callback notify
  immediately (semantics now documented on `batch`); subscriptions added
  mid-notify receive no in-flight event (documented on `notify`);
  prefix-path liveness (`subscribe_under` unsubscribed mid-notify);
  self-unsubscribing subscribers firing exactly once
- Group dispatch snapshot tests: a group self-unmounting mid-dispatch
  leaves siblings dispatched; a group mounted mid-dispatch receives no
  in-flight event (next event reaches it)
- First debounced group-async test (existing group async tests all ran
  debounce 0): re-triggers inside the window reschedule — one run, one
  application, exact validating transitions

### Tests

- 350 tests on js, 326 on wasm (+12)

## [0.8.5] - 2026-09-29

### Fixed

A full reentrancy/staleness audit of the group and array-op paths (the
field-side guards from 0.8.x had no group-side counterparts):

- **Stale-index abort on groups (crash)**: every group-side `lens.get` —
  change dispatch, mount/unmount listeners, sync and async validation,
  group submission — read the raw array index and aborted on js when the
  group's element had been removed. All paths now read through
  `Lens::try_get` and skip the stale slot (mirrors the field-side fix)
- **Out-of-range array-op indices corrupted the meta layout**: `remove`
  with a negative index shifted every slot's meta onto phantom keys while
  values stayed unchanged; `remove` beyond the end deleted the last live
  element's meta; `swap` with one bad index exiled a slot's subtree to a
  phantom key; `move` from an out-of-range source shifted all meta up.
  All four are now full no-ops (values AND meta), and `move` clamps `to`
  to the array bounds so the meta remap lands where the element does
  (insert already clamped)
- **Distributed-error ownership never migrated with array remaps**: a
  group's owned records kept pre-operation indices after remove/insert/
  swap/move, so (a) errors the remap moved became permanent orphans —
  `is_fields_valid` stayed false forever and the group could never submit
  again — and (b) the clear on a clean re-validation could wipe a
  different writer's error that the remap re-seated onto an owned key.
  Records now follow the same shift/drop as the meta, and clearing is
  compare-and-swap on the distributed content: another writer's
  replacement wins and stays
- **Lazy iteration over live maps ran user callbacks**: the group
  dispatch, the dep-watch dispatch, and both submit loops (form and
  group) iterated `Map::keys()` while validators/listeners/subscriber
  callbacks could mount/unmount fields and groups mid-loop — silently
  skipping or repeating entries (a skipped submit validator could let an
  invalid form through). All four paths iterate snapshots now
- **Phantom state after mid-notify unmounts**: `FieldApi::set_value` /
  `handle_blur` / `mount` and the group dispatch / `set_value` / `mount` /
  `handle_submit` kept scheduling validation and async runs on instances
  that user code had unmounted mid-notification — the fresh async run
  passed the race guard and landed errors and validating flags on the
  dead instance. All continuation points re-check liveness (dead =
  previously mounted, since unmounted; never-mounted handles keep
  pure-accessor semantics)
- **`form.reset` resurrected in-flight async validation**: neither the
  field nor the group side aborted pending runs, so completions landed
  errors on the freshly reset state once the clock advanced. Field regs
  gain an `abort_async` closure; the group reset aborts first
- **`group.set_value` never dispatched nested groups**: a group write
  covered the nested groups' whole subtree but only ran the writing
  group's own validation — nested onChange listeners, change validation
  and error distribution all stayed stale, and dependency watches never
  fired. Nested groups (keys extending the written key) now dispatch, in
  addition to the fields' dep watches
- **`unregister_field` leaked the field's submit validator**: an
  unmounted field's onSubmit validator kept running on every later
  submission (and could materialize meta for the dead field). It is now
  removed together with the registration and the dependency watches

### Tests

- 338 tests on js, 314 on wasm (+16: array-op guard, ownership-migration,
  CAS-clear, stale-group, reentrancy, reset-abort, nested-dispatch,
  submit-cleanup regressions)

## [0.8.4] - 2026-09-25

### Added

- Extreme-input robustness tests (fifth audit perspective): every array
  operation under out-of-range/negative indices and on empty arrays
  (clamp / no-op semantics, never a crash — insert clamps, remove/swap/
  move/replace are no-ops, clear empties safely); stale-index reads
  through lenses after structural removals; six-level nested structured
  keys composing and prefix-dispatching through groups; unicode string
  values through length validation (codepoint counting); zero-delay and
  million-ms timers at exact virtual-clock boundaries. All green — the
  extreme-input surface needed no fixes, and is now pinned
- Line-ending hygiene: the four files predating .gitattributes had stale
  CRLF working-tree checkouts (blob content already LF); refreshed

### Tests

- 322 tests on js, 298 on wasm

## [0.8.3] - 2026-09-25

### Fixed

- **Unsubscribing mid-notify still delivered to removed subscribers** (the
  7th test-surfaced bug): `Subscriptions::notify` / `notify_all` / the
  batch flush iterated the subscriber array while callbacks could rebuild
  it (an unsubscribe inside a listener) — the in-flight dispatch kept
  iterating the stale snapshot, firing callbacks that had just been
  removed. All three paths now iterate a snapshot and re-check liveness
  after every callback, so removals take effect immediately without
  breaking the dispatch. Guarded by a three-subscriber
  unsubscribe-during-notify test

### Added

- Reentrancy and notification-storm tests (the paths React apps actually
  hit): a change listener cascading writes into other fields; nested
  batches flushing exactly once; a listener's batch-inner writes staying
  coalesced; submit re-entered from a change listener staying bounded
- React StrictMode double-mount tests: field and group
  mount→unmount→mount sequences keep exactly one live registration
  (stale-instance unmounts are no-ops); bridges attach→detach→attach
  resubscribe cleanly; double mount/unmount are idempotent

### Tests

- 317 tests on js, 293 on wasm

## [0.8.2] - 2026-09-25

### Documentation

- **Doc-test coverage gaps filled** (a documentation audit found every
  user-facing package documented, but not every feature):
  - `core/README.mbt.md`: new "Field reset and subtree subscriptions"
    section — `subscribe_under` (the prefix subscription behind
    GroupBridge) and `FieldApi::reset`
  - `schema/README.mbt.md`: new "schema as a per-field validator" section
    — `schema_field_validator` feeding per-field slots (previously only
    the group validator had a doc test)
  - `examples/README.md`: bench section (500-field timing smoke, what each
    phase measures)
- Audit results folded in: all pub APIs carry `///` doc comments (100%
  coverage); counts verified consistent across README/CHANGELOG/status
  notes

### Tests

- 308 tests on js, 288 on wasm (+2 doc tests)

## [0.8.1] - 2026-09-25

### Fixed

Both surfaced by a group × structural-change edge-case audit:

- **Array operations scrambled group-distributed errors**: ops wrote the
  value first (dispatching the containing group's change re-validation
  against the OLD meta layout) and remapped meta afterwards — the freshly
  distributed errors then got shifted again by the remap, landing on the
  wrong elements. insert/remove/swap/move now remap meta BEFORE the value
  write, so the re-validation dispatch sees a layout consistent with the
  new values. Guarded by a new test (distributed errors migrate across a
  remove and the group re-syncs against the new indices)
- **Group cleanup could materialize meta entries out of thin air**: both
  clear paths (stale-slot clearing on re-validation, unmount cleanup)
  called `meta.update`, which INSERTS a default entry for absent keys —
  re-creating entries for vacated array slots and deleted fields, breaking
  the "unmounted fields have no meta entry" contract. Clearing now skips
  absent keys. Guarded by tests (delete_field under a group; vacated-slot
  hygiene after remove)

### Added

- Edge-case tests pinning group × structural-change semantics: form
  `update` preserves a mounted group's registration and submission/error
  state; a group's Submit error slot persists through value changes and
  clears on re-submission (mirroring field-level slot semantics)

### Tests

- 306 tests on js, 286 on wasm

## [0.8.0] - 2026-09-25

### Added

- **`rules`: `one_of` / `one_of_str`** — enum-membership validation for
  select/dropdown fields (any `Eq` type; string convenience wrapper),
  completing the built-in rule set alongside equals/must_be_true
- **`rules` doc-tests** (`README.mbt.md`): executable documentation for
  the rule families — required/length chaining (with the documented
  error-concatenation semantics of `then`), membership, format rules with
  custom messages, and the custom-closure escape hatch
- **`react` doc-tests** (`README.mbt.md`, js target): executable
  documentation for the bridge trio — FieldBridge refresh-on-write,
  GroupBridge submit gating on group validity, FormBridge submit-lifecycle
  reflection. Every user-facing package (core, rules, schema, react) now
  ships doc-tests

### Tests

- 302 tests on js, 282 on wasm (one_of unit tests + 4 doc-tests;
  react doc-tests run on js only, matching the package's target)

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
