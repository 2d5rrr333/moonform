// Regression: array operations on forms with mounted per-element fields
// (stale-index safety). The bug: after remove/insert, mounted fields whose
// index no longer exists crashed change-validation dispatch (Array::at
// out-of-bounds abort is uncatchable on js). Fix: dispatchers read through
// Lens::try_get and skip stale slots.

///|
test "regression: change-validation skips stale array slots after remove" {
  let form = FormApi::make({ names: ["one", "two", "three"], })
  // mount a field on slot 2
  let f2 = form.field(at(names_l(), 2))
  f2.mount()
  // remove slot 0: slot 2 becomes slot 1; the OLD slot-2 registration
  // (key names.2) is stale for the rest of this test's dispatch window
  form.remove_value(names_l(), 0)
  // any further set_value on the array must not abort
  form.set_value(at(names_l(), 1), "TWO") // dispatch touches all mounted
  assert_eq(form.values().names, ["two", "TWO"])
}

///|
test "regression: stale slot mount-validation is skipped" {
  let form = FormApi::make({ names: ["a"], })
  // a field addressed at an out-of-range index: mounting must not abort
  let f9 = form.field(
    at(names_l(), 9),
    on_change_validate=validator(v => if v.length() == 0 { ["req"] } else { [] }),
  )
  f9.mount() // mount runs Mount validation through try_get → skip
  assert_eq(f9.meta().errors(), [])
}

///|
test "regression: async validation skips stale slots" {
  let clock = VirtualClock::make()
  let form = FormApi::make({ names: ["a", "b"], }).with_clock(clock.clock())
  let f1 = form.field(
    at(names_l(), 1),
    on_change_async_validate=async_validator((v, c, done) => {
      let _ = c.schedule(10, () => done(if v == "b" { ["bad"] } else { [] }))
    }),
  )
  f1.mount()
  f1.set_value("b") // schedules async validation
  form.remove_value(names_l(), 0) // slot 1 becomes slot 0; old key stale
  clock.run_all() // stale completion must be applied harmlessly or skipped
  assert_eq(form.values().names, ["b"])
}

///|
test "lens try_get: stale index is None, live index is Some" {
  let lens = at(names_l(), 1)
  let form = FormApi::make({ names: ["a"], })
  assert_true(lens.try_get(form.values()) is None) // index 1 gone
  let lens0 = at(names_l(), 0)
  assert_true(lens0.try_get(form.values()) is Some("a"))
  // composed lens propagates staleness
  let deep = at(friends_l_dbg(), 5).compose(dbg_nm_l())
  assert_true(deep.try_get({ friends: [{ nm: "x", }], }) is None)
}

///|
test "stale-slot field is_dirty: slot vanished vs default present" {
  let form = FormApi::make({ names: ["a"], })
  let f3 = form.field(at(names_l(), 3), default="d")
  f3.mount()
  assert_false(f3.is_dirty()) // both current and default: stale → not dirty
}

///|
fn friends_l_dbg() -> Lens[DbgForm, Array[DbgItem]] {
  field("friends", f => f.friends, (_f, xs) => { friends: xs, })
}

///|
fn dbg_nm_l() -> Lens[DbgItem, String] {
  field("nm", f => f.nm, (_f, n) => { nm: n, })
}

///|
struct DbgItem {
  nm : String
} derive(Eq, Debug)

///|
struct DbgForm {
  friends : Array[DbgItem]
} derive(Eq, Debug)
