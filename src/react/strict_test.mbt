// React StrictMode double-mount audit: mount → unmount → mount sequences
// hit the stale-instance guards on both fields and groups; bridges attach /
// detach / attach over the same lifecycle.

///|
struct StrictVals {
  kname : String
  kstep : StrictStep
} derive(Eq, Debug)

///|
pub extend StrictVals with Debug::{to_repr}

///|
pub extend StrictVals with Eq::{not_equal, equal}

///|
struct StrictStep {
  ktitle : String
} derive(Eq, Debug)

///|
pub extend StrictStep with Debug::{to_repr}

///|
pub extend StrictStep with Eq::{not_equal, equal}

///|
fn strict_name_l() -> @core.Lens[StrictVals, String] {
  @core.field("name", (v : StrictVals) => v.kname, (v, n) => { ..v, kname: n, })
}

///|
fn strict_step_l() -> @core.Lens[StrictVals, StrictStep] {
  @core.field("step", (v : StrictVals) => v.kstep, (v, s) => { ..v, kstep: s, })
}

///|
fn strict_title_l() -> @core.Lens[StrictVals, String] {
  strict_step_l().compose(
    @core.field("title", (s : StrictStep) => s.ktitle, (_s, t) => { ktitle: t, }),
  )
}

///|
test "strict: field mount-unmount-mount keeps exactly one live registration" {
  let form = @core.FormApi::make({ kname: "", kstep: { ktitle: "", }, })
  let first = form.field(
    strict_name_l(),
    on_change_validate=@core.validator(v => {
      if v == "" {
        ["required"]
      } else {
        []
      }
    }),
  )
  first.mount()
  first.unmount() // StrictMode: first instance torn down
  let second : @core.FieldApi[StrictVals, String] = form.field(
    strict_name_l(),
    on_change_validate=@core.validator(v => {
      if v == "" {
        ["required v2"]
      } else {
        []
      }
    }),
  )
  second.mount()
  // the second mount owns the key now: its validator runs
  form.set_value(strict_name_l(), "")
  assert_eq(second.meta().errors(), ["required v2"])
  // the stale first instance's unmount must be a no-op (no listener, no
  // registration damage)
  first.unmount()
  form.set_value(strict_name_l(), "")
  assert_eq(second.meta().errors(), ["required v2"])
  assert_true(form.has_field_meta(strict_name_l().key))
}

///|
priv struct StrictCounter {
  mut n : Int
}

///|
test "strict: group mount-unmount-mount keeps exactly one live dispatch" {
  let form = @core.FormApi::make({ kname: "", kstep: { ktitle: "", }, })
  let group_hits : StrictCounter = { n: 0, }
  let first : @core.FormGroupApi[StrictVals, StrictStep] = form.group(
    strict_step_l(),
    on_change=_g => group_hits.n = group_hits.n + 1,
  )
  first.mount()
  first.unmount()
  let second : @core.FormGroupApi[StrictVals, StrictStep] = form.group(
    strict_step_l(),
    on_change=_g => group_hits.n = group_hits.n + 1,
  )
  second.mount()
  // only the second group receives change dispatch
  form.set_value(strict_title_l(), "x")
  assert_eq(group_hits.n, 1)
  // stale unmount must not remove the live registration
  first.unmount()
  form.set_value(strict_title_l(), "y")
  assert_eq(group_hits.n, 2)
}

///|
test "strict: bridge attach-detach-attach resubscribes cleanly" {
  let form = @core.FormApi::make({ kname: "", kstep: { ktitle: "", }, })
  let bridge = @react.FieldBridge::make(form, strict_name_l())
  bridge.attach()
  bridge.set_value("a")
  assert_eq(bridge.state().value, "a")
  bridge.detach()
  bridge.set_value("b") // detached: snapshot stays stale by contract
  assert_eq(bridge.state().value, "a")
  bridge.attach() // re-attach: subscription live again
  bridge.set_value("c")
  assert_eq(bridge.state().value, "c")
  // rev: 1 (the "a" refresh while attached) + 2 (the "c" refresh after
  // re-attach) — the detached "b" write never refreshed, per contract
  assert_eq(bridge.state().rev, 2)
}

///|
test "strict: double unmount and double mount are idempotent" {
  let form = @core.FormApi::make({ kname: "", kstep: { ktitle: "", }, })
  let field : @core.FieldApi[StrictVals, String] = form.field(strict_name_l())
  field.mount()
  field.mount() // second mount is a no-op
  field.unmount()
  field.unmount() // second unmount is a no-op
  // values preserved through the mount cycle
  assert_eq(form.get_value(strict_name_l()), "")
}
