# moonform

Native headless form state library for MoonBit. **Architecture inspired by [TanStack Form](https://github.com/TanStack/form)** (MIT).

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/2d5rrr333/moonform/actions/workflows/ci.yml/badge.svg)](https://github.com/2d5rrr333/moonform/actions/workflows/ci.yml)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-2d5rrr333%2Fmoonform-orange)](https://mooncakes.io/docs/#/2d5rrr333/moonform/)

English | [中文](README.md)

## Install

```bash
# core + built-in rules (zero third-party deps)
moon add 2d5rrr333/moonform/core
moon add 2d5rrr333/moonform/rules
```

```json
// then import per package in moon.pkg:
{
  "import": [
    "2d5rrr333/moonform/core",
    "2d5rrr333/moonform/rules"
  ]
}
```

Optional packages: `/schema` (moonschema adapter — vendored inside this module, no extra deps), `/react` (requires `moon add tiye/react`), `/lens-gen` (accessor generator).

## What it is

**Why**: mooncakes.io already has rendering layers (tiye/react etc.) and
validation layers (moonschema etc.) — but the form-state orchestration layer
was entirely missing. Field state machines, validation timing (debounce/
race-abort), array-field operations, submit lifecycles: error-prone glue
code every web project rewrites by hand. moonform fills that layer: headless
(no rendering framework lock-in), isomorphic across three targets (one
validation definition for client and server), with correctness specified by
behavior-equivalent translation of the upstream test suite (auditable, not
self-claimed).

- **Headless form state machine** — field values, dirty/touched, error derivation, subscriptions, submit orchestration. Behavior-parity with `@tanstack/form-core@1.33.5` via translated upstream tests ([upstream/PARITY.md](upstream/PARITY.md))
- **Structured field accessors (lens)** — replaces dot-path strings with `(key, get, set)` triples: compile-time safe, rename-safe; array operations (push/insert/remove/swap/move/replace) with meta migration
- **Field groups (FormGroup)** — lens-prefix grouping: group-level validators (group errors + distribution to child fields, deferred for not-yet-mounted fields), group-scoped submission (never touches the form's submit state), form-level onChange/onChangeGroup listeners with independent debounce
- **Resolver protocol** — pluggable validators: built-in lightweight rules + moonschema (zod-style JSON Schema) adapter; a schema works as a field validator (`schema_field_validator`) or a **group validator** (`schema_group_validator`, distributing errors to child fields by group-relative paths)
- **Adapter protocol** — the core never renders; the tiye/react adapter bridges via `use_sync_external_store`
- **Multi-target** — core/rules are dependency-free and compile to js/wasm/native; the same validation definition runs on server and client (isomorphic)
- **Virtual clock** — debounce/race-abort/async-submit against an injected `Clock` protocol: deterministic virtual-time tests, no real timers

## Packages

| Package | Deps | Notes |
|---|---|---|
| `core` | none | state machine, Key/Lens, MetaStore, subscriptions, Clock, Validator, FormGroup, submit |
| `rules` | none | required/min/max/length/pattern/contains/equals/non_blank/numeric/must_be_true/custom closures |
| `schema` | vendored moonschema | moonschema adapter (JSON-Pointer error paths → field slots) |
| `react` | tiye/react | FieldBridge + use_field, GroupBridge + use_group (js target) |
| `lens-gen` | none | .mbti-driven accessor generator (incremental enhancement) |
| `examples/login` | all | login form example (headless-verified) |
| `examples/wizard` | all | FormGroup multi-step form example (headless-verified) |

## Quick start

```moonbit
struct Login {
  email : String
  password : String
} derive(Eq, Debug)

fn email_l() -> @core.Lens[Login, String] {
  @core.field("email", v => v.email, (v, e) => { ..v, email: e })
}

let form = @core.FormApi::make({ email: "", password: "" })
let email = form.field(
  email_l(),
  on_change_validate=@rules.required().then(@rules.min_length(3)),
)
email.mount()
email.set_value("ab")            // → errors: ["Must be at least 3 characters"]
email.handle_blur()              // → touched + blurred
form.handle_submit(submit_options=...) // validation gate / submit lifecycle
```

Array fields:

```moonbit
// fn friends_l() -> Lens[Form, Array[Friend]] — accessor defined as above
form.push_value(friends_l(), friend)
form.remove_value(friends_l(), 0)  // friends[1].name errors migrate to friends[0].name
form.swap_values(friends_l(), 0, 2)
```

Async validation (virtual clock, deterministic tests):

```moonbit
let clock = @core.VirtualClock::make()
let form = @core.FormApi::make(values).with_clock(clock.clock())
let field = form.field(
  email_l(),
  on_change_async_debounce_ms=500,
  on_change_async_validate=@core.async_validator(...),
)
field.set_value("x")
clock.run_all()   // debounce window + validation, one tick
```

Field groups (group validation + error distribution + group submit):

```moonbit
// fn step1_l() -> Lens[Form, Step] — accessor defined as above
let step1 = form.group(
  step1_l(),
  on_submit_validate=@core.group_validator_value(g => {
    if g.name == "" {
      @core.GroupValidationResult::group_and_fields(
        "Step incomplete",
        [(@core.Key::field("name"), "Name is required")],
      )
    } else {
      @core.GroupValidationResult::valid()
    }
  }),
)
step1.mount()
step1.handle_submit(
  on_group_submit=(value, _meta) => submit_step1(value),  // form submit state untouched
  on_group_submit_invalid=() => show_group_errors(),
)
```

A group validator can also be a compiled moonschema schema (errors
distribute to child fields by their JSON-Pointer paths relative to the
group — see the `/schema` package):

```moonbit
let step_schema = @builder.object({ "name": @builder.string().min_len(2) }).compile()...
let step1 = form.group(
  step1_l(),
  on_submit_validate=@formSchema.schema_group_validator(step_schema),
)
```

React (tiye/react):

```moonbit
let bridge = @formreact.FieldBridge::make(form, email_l())
let handle = @formreact.use_field_handle(bridge)
let state = @react.use_sync_external_store(
  () => handle.subscribe(),
  () => handle.get_snapshot(),
)
// state.value / state.errors / state.is_touched ...
```

Group state (React) — `GroupBridge` prefix-subscribes to the whole subtree;
any child change (distributed errors included) refreshes the group snapshot:

```moonbit
let step1 = form.group(step1_l(), on_submit_validate=...)
let gbridge = @formreact.GroupBridge::make(step1)
let ghandle = @formreact.use_group_handle(gbridge)
let gstate = @react.use_sync_external_store(
  () => ghandle.subscribe(),
  () => ghandle.get_snapshot(),
)
// gstate.value / gstate.errors / gstate.is_valid / gstate.can_submit ...
gbridge.submit(on_group_submit=(v, _) => submit_step1(v))
```

More in [examples/README](src/examples/README.md). **Browser demos** (login form + FormGroup multi-step wizard, 14 headless browser checks): [web/](web/README.md).

## Tests & acceptance

```bash
moon test --target js      # 277 tests (incl. upstream translations + doc-tests)
moon test --target wasm    # 266 tests
moon test --target native  # verified in CI (five green GitHub Actions jobs)
moon run src/examples/login --target js   # example verification
```

Three-target `moon check` with zero warnings; CI covers check×3 targets +
test×3 targets + the example run ([workflow](.github/workflows/ci.yml)).

Upstream parity: **185 translated tests** cover the behavior semantics of the
form-core@1.33.5 342-case suite (FormGroup's 31 and FieldGroup's 20 included);
exemptions (utils dot-path machinery / mergeForm / type-level tests, etc.)
and deliberate deviations (value semantics / virtual clock / FieldGroup
subsumed by lens composition, 9 items) are recorded case by case in
[upstream/PARITY.md](upstream/PARITY.md).

## Credits

- [TanStack Form](https://github.com/TanStack/form) (MIT) — behavior-semantics baseline
- [QuietlyChan/moonschema](https://github.com/QuietlyChan/moonschema) (Apache-2.0) — schema validation engine, vendored at `src/vendor/moonschema`
- [tiye/react](https://mooncakes.io/docs/#/tiye/react/) — React bindings

## License

MIT
