// Roster example: a dynamic array form — add/remove/swap friends with
// per-field validation and meta (error) migration, plus submit gating.
// Headless verification: moon run src/examples/roster --target js

///|
struct Friend {
  name : String
  age : Int
} derive(Eq, Debug)

///|
struct RosterForm {
  friends : Array[Friend]
} derive(Eq, Debug)

///|
struct Counts {
  mut submits : Int
  mut invalids : Int
}

///|
fn friends_l() -> @core.Lens[RosterForm, Array[Friend]] {
  @core.field("friends", f => f.friends, (_, xs) => { friends: xs, })
}

///|
fn friend_name_l() -> @core.Lens[Friend, String] {
  @core.field("name", f => f.name, (f, n) => { ..f, name: n, })
}

///|
fn friend_name_field(
  form : @core.FormApi[RosterForm],
  i : Int,
) -> @core.FieldApi[RosterForm, String] {
  form.field(
    @core.at(friends_l(), i).compose(friend_name_l()),
    on_change_validate=@core.validator(v => {
      if v.length() < 2 {
        ["name: min 2 chars"]
      } else {
        []
      }
    }),
  )
}

///|
fn build_form() -> @core.FormApi[RosterForm] {
  @core.FormApi::make({
    friends: [{ name: "alice", age: 30, }, { name: "bob", age: 25, }],
  })
}

///|
fn main raise {
  let form = build_form()
  let counts : Counts = { submits: 0, invalids: 0, }

  // 1) mount per-element fields for the initial two friends
  let f0_name = friend_name_field(form, 0)
  let f1_name = friend_name_field(form, 1)
  f0_name.mount()
  f1_name.mount()

  // 2) a validation error sits on friends[1].name
  f1_name.set_value("b")
  assert_true(f1_name.meta().has_errors())

  // 3) remove friends[0]: the error on friends[1].name migrates to [0]
  form.remove_value(friends_l(), 0)
  assert_eq(form.values().friends.length(), 1)
  let moved = friends_l().key.push_idx(0).push_field("name")
  let moved_errs = form.field_meta(moved).errors()
  assert_eq(moved_errs, ["name: min 2 chars"])
  // the vacated slot's meta is gone
  assert_false(form.has_field_meta(friends_l().key.push_idx(1)))

  // 4) push a new friend: new slot starts clean
  form.push_value(friends_l(), { name: "carol", age: 40, })
  let f2_name = friend_name_field(form, 2)
  f2_name.mount()
  assert_false(f2_name.meta().has_errors())

  // 5) swap: value + meta travel together (array is [b-error, carol])
  form.swap_values(friends_l(), 0, 1)
  assert_eq(form.values().friends[0].name, "carol")
  assert_eq(form.values().friends[1].name, "b")
  // the "b" error (was at slot 0) is now on slot 1's key
  let moved2 = friends_l().key.push_idx(1).push_field("name")
  let moved2_errs = form.field_meta(moved2).errors()
  assert_eq(moved2_errs, ["name: min 2 chars"])

  // 6) submit is blocked while the error exists
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_v, done) => {
        counts.submits = counts.submits + 1
        done(@core.SubmitResult::ok())
      }),
    ),
    on_submit_invalid: Some(_ => counts.invalids = counts.invalids + 1),
  })
  assert_eq(counts.submits, 0)
  assert_eq(counts.invalids, 1)

  // 7) fix the name, submit succeeds
  form.set_value(@core.at(friends_l(), 1).compose(friend_name_l()), "bobby")
  assert_eq(form.field_meta(moved2).errors(), [])
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_v, done) => {
        counts.submits = counts.submits + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  assert_eq(counts.submits, 1)
  assert_true(form.is_submit_successful())

  println("roster example: all checks passed")
}
