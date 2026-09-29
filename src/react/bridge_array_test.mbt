// Array-op × bridge integration (the 0.8.7 audit round): stale slots
// never abort (the core's try_get contract reached the adapter layer),
// structural changes refresh element bridges, derived dirty replaces the
// sticky flag, the live validating signal reaches FormState, and
// attach_with_notify drives its callback.

///|
struct AbItem {
  abname : String
} derive(Eq, Debug)

///|
pub extend AbItem with Debug::{to_repr}

///|
pub extend AbItem with Eq::{not_equal, equal}

///|
struct AbForm {
  abitems : Array[AbItem]
} derive(Eq, Debug)

///|
pub extend AbForm with Debug::{to_repr}

///|
pub extend AbForm with Eq::{not_equal, equal}

///|
fn ab_items_l() -> @core.Lens[AbForm, Array[AbItem]] {
  @core.field("items", (f : AbForm) => f.abitems, (_f, xs) => { abitems: xs, })
}

///|
fn ab_name_l() -> @core.Lens[AbItem, String] {
  @core.field("name", (i : AbItem) => i.abname, (_i, n) => { abname: n, })
}

///|
fn ab_name_at(i : Int) -> @core.Lens[AbForm, String] {
  @core.at(ab_items_l(), i).compose(ab_name_l())
}

///|
test "bridge: stale slot after remove keeps the last value, never aborts" {
  let form = @core.FormApi::make({
    abitems: [{ abname: "a", }, { abname: "b", }],
  })
  let bridge = @react.FieldBridge::make(form, ab_name_at(1))
  bridge.attach()
  assert_eq(bridge.state().value, "b")
  // remove(0) shifts element 1 into slot 0 — the vacated slot 1 no longer
  // exists; the bridge's refresh (fired by the structural notification)
  // used to abort inside lens.get
  form.remove_value(ab_items_l(), 0)
  // the bridge at POSITION 1 now reads the (stale) slot: it keeps the
  // last live value instead of crashing
  assert_eq(bridge.state().value, "b")
  bridge.detach()
}

///|
test "bridge: swap refreshes element bridges (values follow the swap)" {
  let form = @core.FormApi::make({
    abitems: [{ abname: "a", }, { abname: "b", }],
  })
  // mounted fields: their meta entries are what structural notifications
  // key off (adapters mount per-slot fields)
  form.field(ab_name_at(0)).mount()
  form.field(ab_name_at(1)).mount()
  let b0 = @react.FieldBridge::make(form, ab_name_at(0))
  let b1 = @react.FieldBridge::make(form, ab_name_at(1))
  b0.attach()
  b1.attach()
  assert_eq(b0.state().value, "a")
  assert_eq(b1.state().value, "b")
  // swap: the values moved onto the other bridges' positions — their own
  // keys were never written, so only the structural notification refreshes
  form.swap_values(ab_items_l(), 0, 1)
  assert_eq(b0.state().value, "b")
  assert_eq(b1.state().value, "a")
  b0.detach()
  b1.detach()
}

///|
test "bridge: remove refreshes the shifted element bridges" {
  let form = @core.FormApi::make({
    abitems: [{ abname: "a", }, { abname: "b", }, { abname: "c", }],
  })
  form.field(ab_name_at(0)).mount()
  form.field(ab_name_at(1)).mount()
  form.field(ab_name_at(2)).mount()
  let b1 = @react.FieldBridge::make(form, ab_name_at(1))
  b1.attach()
  assert_eq(b1.state().value, "b")
  form.remove_value(ab_items_l(), 0) // "b" shifts into slot 0, "c" into 1
  // position 1 now holds "c": the bridge reads positionally
  assert_eq(b1.state().value, "c")
  b1.detach()
}

///|
test "group bridge: group on an array element survives the element's removal" {
  let form = @core.FormApi::make({
    abitems: [{ abname: "a", }, { abname: "b", }],
  })
  let g1 = form.group(@core.at(ab_items_l(), 1))
  let bridge = @react.GroupBridge::make(g1)
  bridge.attach()
  assert_eq(bridge.state().value.abname, "b")
  // removing element 0 shrinks the array: index 1 no longer exists — the
  // snapshot keeps the last live value instead of aborting
  form.remove_value(ab_items_l(), 0)
  assert_eq(bridge.state().value.abname, "b")
  // any further structural writes stay safe too
  form.remove_value(ab_items_l(), 0)
  assert_eq(bridge.state().value.abname, "b")
  bridge.detach()
}

///|
test "bridge: is_dirty is derived — reverting the value clears it" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = @react.FieldBridge::make(form, simple_name_l())
  bridge.attach()
  assert_false(bridge.state().is_dirty) // untouched: not dirty
  bridge.set_value("b")
  assert_true(bridge.state().is_dirty)
  bridge.set_value("a") // back to the default: NOT dirty (upstream isDirty)
  assert_false(bridge.state().is_dirty)
  bridge.detach()
}

///|
test "form bridge: is_validating lights up during async validation" {
  let clock = @core.VirtualClock::make()
  let form = @core.FormApi::make({ name: "", }).with_clock(clock.clock())
  let field = form.field(
    simple_name_l(),
    on_change_async_validate=@core.async_validator((_v, _c, done) => done([])),
  )
  field.mount()
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  assert_false(bridge.state().is_validating)
  field.set_value("x") // launches the (synchronous-completing) async run
  clock.run_all()
  // the run started and finished: the flag is back down, and it was never
  // stuck on the dead default-state flag
  assert_false(bridge.state().is_validating)
  // an in-flight run (completing later) must show up in the snapshot
  let slow = form.field(
    simple_name_l(),
    on_change_async_validate=@core.async_validator((_v, c, done) => {
      let _ = c.schedule(50, () => done([]))
    }),
  )
  slow.mount()
  slow.set_value("y")
  assert_true(bridge.state().is_validating) // in flight
  clock.run_all()
  assert_false(bridge.state().is_validating)
  bridge.detach()
}

///|
struct AbCount {
  mut n : Int
}

///|
test "bridge: attach_with_notify drives the notify callback" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = @react.FieldBridge::make(form, simple_name_l())
  let notifies : AbCount = { n: 0, }
  bridge.attach_with_notify(() => notifies.n = notifies.n + 1)
  let base = bridge.state().rev
  bridge.set_value("b")
  assert_eq(notifies.n, 1) // the refresh called notify (re-render signal)
  assert_true(bridge.state().rev > base)
  bridge.detach()
  bridge.set_value("c")
  assert_eq(notifies.n, 1) // detached: no further notifies
  // re-attach rebuilds the snapshot but does NOT notify (no re-render
  // storm from the subscribe path itself)
  bridge.attach_with_notify(() => notifies.n = notifies.n + 1)
  assert_eq(notifies.n, 1)
  assert_eq(bridge.state().value, "c") // fresh after re-attach
}

///|
test "group bridge: unmounting the group refreshes the snapshot" {
  let form = @core.FormApi::make({ name: "", })
  let group = form.group(
    @core.identity(),
    on_mount_validate=@core.group_validator_value(_g => {
      @core.GroupValidationResult::group_error("boom")
    }),
  )
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  assert_false(bridge.state().is_group_valid) // the mount error shows
  group.unmount()
  // the unmount cleared the group's state — the snapshot must follow
  assert_eq(bridge.state().errors.length(), 0)
  bridge.detach()
}
