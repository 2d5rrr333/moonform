// Array meta migration, translated from form-core@1.33.5 FormApi.spec.ts
// ("shift meta (nested) when removing array values", "swap meta (nested) ...",
// "move meta (nested) ... forward/backward", and the insert-shift case).

///|
struct UserName {
  name : String
  surname : String
} derive(Eq, Debug)

///|
struct UsersForm {
  users : Array[UserName]
} derive(Eq, Debug)

///|
fn users_defaults() -> UsersForm {
  {
    users: [
      { name: "test", surname: "test", },
      { name: "test2", surname: "test2", },
      { name: "test3", surname: "test3", },
    ],
  }
}

///|
fn users_l() -> Lens[UsersForm, Array[UserName]] {
  field("users", f => f.users, (_f, xs) => { users: xs, })
}

///|
fn uname_l() -> Lens[UserName, String] {
  field("name", u => u.name, (u, n) => { ..u, name: n, })
}

///|
fn usurname_l() -> Lens[UserName, String] {
  field("surname", u => u.surname, (u, s) => { ..u, surname: s, })
}

///|
fn user_name_field(
  form : FormApi[UsersForm],
  i : Int,
) -> FieldApi[UsersForm, String] {
  form.field(at(users_l(), i).compose(uname_l()))
}

///|
fn user_surname_field(
  form : FormApi[UsersForm],
  i : Int,
) -> FieldApi[UsersForm, String] {
  form.field(at(users_l(), i).compose(usurname_l()))
}

// upstream: "should shift meta (nested) when removing array values"

///|
test "meta migration: remove shifts nested meta down one slot" {
  let form = FormApi::make(users_defaults())
  let f0n = user_name_field(form, 0)
  let f0s = user_surname_field(form, 0)
  let f1n = user_name_field(form, 1)
  let f1s = user_surname_field(form, 1)
  let f2n = user_name_field(form, 2)
  let f2s = user_surname_field(form, 2)
  f0n.mount()
  f0s.mount()
  f1n.mount()
  f1s.mount()
  f2n.mount()
  f2s.mount()
  f0n.handle_blur()
  f2n.handle_blur()
  f2s.handle_blur()
  assert_true(f0n.meta().is_blurred)
  assert_false(f0s.meta().is_blurred)
  assert_false(f1n.meta().is_blurred)
  assert_false(f1s.meta().is_blurred)
  assert_true(f2n.meta().is_blurred)
  assert_true(f2s.meta().is_blurred)
  form.remove_value(users_l(), 1)
  // values follow remove semantics
  assert_eq(form.values().users, [
    { name: "test", surname: "test", },
    { name: "test3", surname: "test3", },
  ])
  // field2's meta moved onto field1's key
  assert_true(f0n.meta().is_blurred) // untouched slot 0
  assert_false(f0s.meta().is_blurred)
  assert_true(f1n.meta().is_blurred) // was slot 2's meta
  assert_true(f1s.meta().is_blurred)
}

// upstream: "should swap meta (nested) when swapping array values"

///|
test "meta migration: swap exchanges nested meta" {
  let form = FormApi::make({
    users: [
      { name: "test", surname: "test", },
      { name: "test2", surname: "test2", },
    ],
  })
  let f0n = user_name_field(form, 0)
  let f0s = user_surname_field(form, 0)
  let f1n = user_name_field(form, 1)
  let f1s = user_surname_field(form, 1)
  f0n.mount()
  f0s.mount()
  f1n.mount()
  f1s.mount()
  f0n.handle_blur()
  assert_true(f0n.meta().is_blurred)
  assert_false(f0s.meta().is_blurred)
  assert_false(f1n.meta().is_blurred)
  assert_false(f1s.meta().is_blurred)
  form.swap_values(users_l(), 0, 1)
  assert_eq(form.values().users, [
    { name: "test2", surname: "test2", },
    { name: "test", surname: "test", },
  ])
  assert_false(f0n.meta().is_blurred) // slot 0 now holds old slot 1 meta
  assert_false(f0s.meta().is_blurred)
  assert_true(f1n.meta().is_blurred) // blurred meta moved to slot 1
  assert_false(f1s.meta().is_blurred)
}

// upstream: "should swap meta when swapping array values" (errors + blur
// together, with setErrorMap replaced by a seeded submit error)

///|
test "meta migration: swap moves errors and flags together" {
  let form = FormApi::make({
    users: [
      { name: "one", surname: "", },
      { name: "two", surname: "", },
      { name: "three", surname: "", },
    ],
  })
  let f1n = user_name_field(form, 1)
  f1n.mount()
  f1n.handle_blur()
  form
  .meta_store()
  .update(f1n.key(), m => {
    ..m,
    error_map: m.error_map.set(Submit, Some(["test"])),
  })
  assert_true(f1n.meta().is_blurred)
  assert_eq(f1n.meta().errors(), ["test"])
  form.swap_values(users_l(), 1, 2)
  // slot 1 now holds old slot 2 meta (clean); slot 2 holds blur+error
  assert_false(f1n.meta().is_blurred)
  assert_eq(f1n.meta().errors(), [])
  let m2 = form.field_meta(users_l().key.push_idx(2).push_field("name"))
  assert_true(m2.is_blurred)
  assert_eq(m2.errors(), ["test"])
}

// upstream: "should move meta (nested) when moving array values forward"

///|
test "meta migration: move forward carries nested meta" {
  let form = FormApi::make(users_defaults())
  let f0n = user_name_field(form, 0)
  let f0s = user_surname_field(form, 0)
  let f1n = user_name_field(form, 1)
  let f1s = user_surname_field(form, 1)
  let f2n = user_name_field(form, 2)
  let f2s = user_surname_field(form, 2)
  f0n.mount()
  f0s.mount()
  f1n.mount()
  f1s.mount()
  f2n.mount()
  f2s.mount()
  f0n.handle_blur()
  form.move_value(users_l(), 0, 2)
  assert_eq(form.values().users, [
    { name: "test2", surname: "test2", },
    { name: "test3", surname: "test3", },
    { name: "test", surname: "test", },
  ])
  // blurred name meta moved from slot 0 to slot 2
  assert_false(f0n.meta().is_blurred)
  assert_false(f0s.meta().is_blurred)
  assert_false(f1n.meta().is_blurred)
  assert_false(f1s.meta().is_blurred)
  assert_true(f2n.meta().is_blurred)
  assert_false(f2s.meta().is_blurred)
}

// upstream: "should move meta (nested) when moving array values backward"

///|
test "meta migration: move backward carries nested meta" {
  let form = FormApi::make(users_defaults())
  let f0n = user_name_field(form, 0)
  let f1n = user_name_field(form, 1)
  let f2n = user_name_field(form, 2)
  f0n.mount()
  f1n.mount()
  f2n.mount()
  f1n.handle_blur()
  f2n.handle_blur()
  assert_true(f1n.meta().is_blurred)
  assert_true(f2n.meta().is_blurred)
  form.move_value(users_l(), 2, 0)
  assert_eq(form.values().users, [
    { name: "test3", surname: "test3", },
    { name: "test", surname: "test", },
    { name: "test2", surname: "test2", },
  ])
  // slot2's blur moved to slot0; slot1's blur moved to slot2
  assert_true(f0n.meta().is_blurred)
  assert_false(f1n.meta().is_blurred)
  assert_true(f2n.meta().is_blurred)
}

// upstream: "should shift meta (including errors) when inserting an array
// field's primitive value" + "last element" case — insert pushes existing
// meta up and the new slot starts clean

///|
test "meta migration: insert shifts existing meta up, new slot clean" {
  let form = FormApi::make({
    users: [{ name: "test", surname: "", }, { name: "test2", surname: "", }],
  })
  let f0n = user_name_field(form, 0)
  let f1n = user_name_field(form, 1)
  f0n.mount()
  f1n.mount()
  f1n.handle_blur()
  form
  .meta_store()
  .update(f1n.key(), m => {
    ..m,
    error_map: m.error_map.set(Submit, Some(["Invalid value"])),
  })
  form.insert_value(users_l(), 0, { name: "new", surname: "", })
  // values: new element first
  assert_eq(form.values().users.map(u => u.name), ["new", "test", "test2"])
  // old slot0 meta now at slot1; old slot1 (blurred+error) now at slot2
  assert_false(f0n.meta().is_blurred)
  assert_false(f1n.meta().is_blurred)
  let m2 = form.field_meta(users_l().key.push_idx(2).push_field("name"))
  assert_true(m2.is_blurred)
  assert_eq(m2.errors(), ["Invalid value"])
}

// insert at the end: existing meta stays in place

///|
test "meta migration: insert at end leaves existing meta" {
  let form = FormApi::make({ users: [{ name: "test", surname: "", }], })
  let f0n = user_name_field(form, 0)
  f0n.mount()
  f0n.handle_blur()
  form.insert_value(users_l(), 5, { name: "tail", surname: "", }) // OOB → append
  assert_true(f0n.meta().is_blurred) // slot 0 untouched
  assert_false(
    form.has_field_meta(users_l().key.push_idx(1).push_field("name")),
  )
}

// deeper nesting: array of structs with an array field inside — operations
// on the outer array migrate the inner array's per-element meta too

///|
struct Item {
  title : String
  tags : Array[String]
} derive(Eq, Debug)

///|
struct Board {
  items : Array[Item]
} derive(Eq, Debug)

///|
fn board_l() -> Lens[Board, Array[Item]] {
  field("items", b => b.items, (_b, xs) => { items: xs, })
}

///|
fn tags_l() -> Lens[Item, Array[String]] {
  field("tags", i => i.tags, (i, ts) => { ..i, tags: ts, })
}

///|
test "meta migration: nested inner-array meta follows outer remove" {
  let form = FormApi::make({
    items: [{ title: "a", tags: ["x"], }, { title: "b", tags: ["y", "z"], }],
  })
  // meta on items[1].tags.0
  let tag_key = board_l().key.push_idx(1).push_field("tags").push_idx(0)
  form.meta_store().update(tag_key, m => { ..m, is_touched: true, })
  form.remove_value(board_l(), 0)
  // the inner-array meta moved to items[0].tags.0
  let moved = board_l().key.push_idx(0).push_field("tags").push_idx(0)
  assert_true(form.field_meta(moved).is_touched)
  assert_false(form.has_field_meta(tag_key))
}

///|
test "meta migration: inner array ops only touch that array's subtree" {
  let form = FormApi::make({
    items: [{ title: "a", tags: ["x", "y"], }, { title: "b", tags: ["z"], }],
  })
  let items1_tags = board_l().key.push_idx(1).push_field("tags")
  // meta on items[1].tags.0 and items[0].tags.1
  form
  .meta_store()
  .update(items1_tags.push_idx(0), m => { ..m, is_touched: true, })
  form
  .meta_store()
  .update(board_l().key.push_idx(0).push_field("tags").push_idx(1), m => {
    ..m,
    is_touched: true,
  })
  // remove within items[1].tags
  let tags1 = at(board_l(), 1).compose(tags_l())
  form.remove_value(tags1, 0)
  // items[1].tags.0 meta gone (removed); items[0].tags untouched
  assert_false(form.has_field_meta(items1_tags.push_idx(0)))
  assert_true(
    form.field_meta(board_l().key.push_idx(0).push_field("tags").push_idx(1)).is_touched,
  )
}
