// @react.GroupBridge semantics (headless): snapshot identity stability, prefix
// subscription coverage (child-field changes refresh the group snapshot),
// submit wiring, attach/detach lifecycle. (Full React render cycles run in
// the examples app; these tests pin the bridge contract the hook relies on.)

///|
struct GroupSimple {
  account : GroupAccount
  other : String
} derive(Eq, Debug)

///|
struct GroupAccount {
  username : String
} derive(Eq, Debug)

///|
fn gs_account_l() -> @core.Lens[GroupSimple, GroupAccount] {
  @core.field("account", (v : GroupSimple) => v.account, (v, a) => {
    ..v,
    account: a,
  })
}

///|
fn gs_username_l() -> @core.Lens[GroupSimple, String] {
  gs_account_l().compose(
    @core.field("username", (a : GroupAccount) => a.username, (_a, u) => {
      username: u,
    }),
  )
}

///|
fn gs_other_l() -> @core.Lens[GroupSimple, String] {
  @core.field("other", (v : GroupSimple) => v.other, (v, o) => {
    ..v,
    other: o,
  })
}

///|
struct GroupCounter {
  mut n : Int
}

///|
fn gs_required_username() -> @core.GroupValidator[GroupAccount, GroupSimple] {
  @core.group_validator_value(g => {
    if g.username == "" {
      @core.GroupValidationResult::fields([
        (@core.Key::field("username"), "Username is required"),
      ])
    } else {
      @core.GroupValidationResult::valid()
    }
  })
}

///|
test "group bridge: snapshot is identity-stable until a change" {
  let form = @core.FormApi::make({ account: { username: "", }, other: "", })
  let group = form.group(gs_account_l())
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  let s1 = bridge.state()
  let s2 = bridge.state()
  assert_eq(s1.rev, s2.rev) // same snapshot until refresh
  assert_eq(s1.value, { username: "", })
  assert_eq(s1.errors, [])
  assert_true(s1.is_valid)
}

///|
test "group bridge: child-field change refreshes the snapshot" {
  let form = @core.FormApi::make({ account: { username: "", }, other: "", })
  let group = form.group(gs_account_l())
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  let username = form.field(gs_username_l())
  username.mount()
  username.set_value("moon")
  let s = bridge.state()
  assert_eq(s.value, { username: "moon", }) // the group value moved
  assert_true(s.rev > 0) // refreshed by the child-field notification
  bridge.detach()
}

///|
test "group bridge: changes outside the group do not refresh" {
  let form = @core.FormApi::make({ account: { username: "", }, other: "", })
  let group = form.group(gs_account_l())
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  form.set_value(gs_other_l(), "x")
  let s = bridge.state()
  assert_eq(s.rev, 0) // untouched: the change was outside the group
  bridge.detach()
}

///|
test "group bridge: distributed errors surface in the snapshot" {
  let form = @core.FormApi::make({ account: { username: "", }, other: "", })
  let group = form.group(
    gs_account_l(),
    on_submit_validate=gs_required_username(),
  )
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  let submitted : GroupCounter = { n: 0, }
  bridge.submit(on_group_submit=(_v, _meta) => submitted.n = submitted.n + 1, on_group_submit_invalid=() => {
    ()
  })
  let s = bridge.state()
  assert_eq(submitted.n, 0) // blocked
  assert_false(s.is_fields_valid) // distributed field error present
  assert_true(s.is_group_valid) // the group's own slot is clean
  assert_false(s.is_valid)
  assert_eq(s.submission_attempts, 1)
  // fix the value and resubmit: the snapshot recovers
  form.set_value(gs_username_l(), "moonbit")
  bridge.submit(on_group_submit=(_v, _meta) => submitted.n = submitted.n + 1, on_group_submit_invalid=() => {
    ()
  })
  let s2 = bridge.state()
  assert_eq(submitted.n, 1)
  assert_true(s2.is_valid)
  assert_eq(s2.submission_attempts, 2)
  bridge.detach()
}

///|
test "group bridge: detach stops refreshes" {
  let form = @core.FormApi::make({ account: { username: "", }, other: "", })
  let group = form.group(gs_account_l())
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  form.set_value(gs_username_l(), "a")
  let rev_after_a = bridge.state().rev
  bridge.detach()
  form.set_value(gs_username_l(), "b") // no subscription: no refresh
  assert_eq(bridge.state().rev, rev_after_a)
  // the core still holds the new value; a manual refresh catches up
  bridge.refresh()
  assert_eq(bridge.state().value, { username: "b", })
}

///|
test "group bridge: group submit never touches the form submit state" {
  let form = @core.FormApi::make({ account: { username: "ok", }, other: "", })
  let group = form.group(
    gs_account_l(),
    on_submit_validate=gs_required_username(),
  )
  group.mount()
  let bridge = @react.GroupBridge::make(group)
  bridge.attach()
  bridge.submit(on_group_submit=(_v, _meta) => ())
  assert_eq(form.submission_attempts(), 0) // the form never submitted
  assert_false(form.is_submitted())
}

///|
pub extend GroupAccount with Debug::{to_repr}

///|
pub extend GroupAccount with Eq::{not_equal, equal}

///|
pub extend GroupSimple with Debug::{to_repr}

///|
pub extend GroupSimple with Eq::{not_equal, equal}
