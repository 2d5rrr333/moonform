// FieldBridge semantics (headless): snapshot identity stability, change
// refresh, attach/detach lifecycle. (Full React render cycles run in the
// examples app; these tests pin the bridge contract the hook relies on.)

///|
struct Simple {
  name : String
} derive(Eq, Debug)

///|
fn simple_name_l() -> @core.Lens[Simple, String] {
  @core.field("name", s => s.name, (_s, n) => { name: n, })
}

///|
test "bridge: snapshot is identity-stable until a change" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = FieldBridge::make(form, simple_name_l())
  let s1 = bridge.state()
  let s2 = bridge.state()
  assert_eq(s1.rev, s2.rev) // same snapshot until refresh
  assert_eq(s1.value, "a")
  assert_eq(s1.errors, [])
  assert_false(s1.is_touched)
}

///|
test "bridge: set_value refreshes the snapshot via subscription" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = FieldBridge::make(form, simple_name_l())
  bridge.attach()
  bridge.set_value("b")
  let s = bridge.state()
  assert_eq(s.value, "b")
  assert_true(s.is_touched)
  assert_true(s.rev > 0) // refreshed by the core notification
  bridge.detach()
}

///|
test "bridge: detach stops refreshes" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = FieldBridge::make(form, simple_name_l())
  bridge.attach()
  bridge.set_value("b")
  let rev_after_b = bridge.state().rev
  bridge.detach()
  bridge.set_value("c") // no subscription: snapshot must not refresh
  let s = bridge.state()
  assert_eq(s.value, "b") // stale by contract (detached)
  assert_eq(s.rev, rev_after_b)
  // core still holds the new value; a manual refresh catches up
  bridge.refresh()
  assert_eq(bridge.state().value, "c")
}

///|
test "bridge: blur reflects in the snapshot" {
  let form = @core.FormApi::make({ name: "a", })
  let bridge = FieldBridge::make(form, simple_name_l())
  bridge.attach()
  bridge.blur()
  let s = bridge.state()
  assert_true(s.is_touched)
  assert_true(s.is_blurred)
}

///|
test "bridge: errors surface through the snapshot" {
  let form = @core.FormApi::make({ name: "a", })
  let field = form.field(
    simple_name_l(),
    on_change_validate=@core.validator(v => {
      if v == "bad" {
        ["no bad values"]
      } else {
        []
      }
    }),
  )
  field.mount()
  let bridge = FieldBridge::make(form, simple_name_l())
  bridge.attach()
  field.set_value("bad")
  let s = bridge.state()
  assert_eq(s.errors, ["no bad values"])
  assert_false(s.is_valid)
}
