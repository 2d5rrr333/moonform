// MetaStore: key-indexed field metadata, prefix queries, array rekeying.

///|
fn err(msg : String) -> FieldMetaState {
  FieldMetaState::default_meta().with_cause_errors(Change, Some([msg]))
}

///|
let arr : Key = Key::field("friends")

///|
test "get/ensure/update/remove roundtrip" {
  let s = MetaStore::make()
  assert_false(s.contains(arr))
  assert_eq(s.get_or_default(arr), FieldMetaState::default_meta()) // no insert
  assert_false(s.contains(arr))
  let m = s.ensure(arr)
  assert_true(s.contains(arr))
  assert_eq(m, FieldMetaState::default_meta())
  s.update(arr, meta => meta.with_cause_errors(Change, Some(["bad"])))
  match s.get(arr) {
    Some(m) => assert_eq(m.errors(), ["bad"])
    None => fail("expected meta present")
  }
  assert_true(s.get_or_default(arr).has_errors())
  s.remove(arr)
  assert_false(s.contains(arr))
  assert_eq(s.length(), 0)
}

///|
test "update on absent key inserts" {
  let s = MetaStore::make()
  s.update(arr, m => { ..m, is_touched: true, })
  match s.get(arr) {
    Some(m) => assert_true(m.is_touched)
    None => fail("expected inserted meta")
  }
}

///|
test "keys and keys_under in canonical order" {
  let s = MetaStore::make()
  ignore(s.ensure(arr.push_idx(2).push_field("name")))
  ignore(s.ensure(arr.push_idx(0).push_field("name")))
  ignore(s.ensure(arr.push_idx(10).push_field("name")))
  ignore(s.ensure(arr))
  ignore(s.ensure(Key::field("user").push_field("email")))
  // keys_under: strictly under friends, numeric index order (0 < 2 < 10,
  // not string order "10" < "2")
  assert_eq(s.keys_under(arr).map(k => k.render()), [
    "friends.0.name", "friends.2.name", "friends.10.name",
  ])
  // keys: Field segments before Idx segments; user.email before friends.*
  // keys: length-first ordering (friends[1 seg] < user.email[2] < friends.0.name[3])
  assert_eq(s.keys().map(k => k.render()), [
    "friends", "user.email", "friends.0.name", "friends.2.name", "friends.10.name",
  ])
}

///|
test "keys_under excludes the prefix itself" {
  let s = MetaStore::make()
  ignore(s.ensure(arr))
  ignore(s.ensure(arr.push_idx(0)))
  assert_eq(s.keys_under(arr).length(), 1)
  assert_eq(s.keys().length(), 2)
}

///|
test "clear_under removes subtree only" {
  let s = MetaStore::make()
  ignore(s.ensure(arr.push_idx(0).push_field("name")))
  ignore(s.ensure(arr.push_idx(1).push_field("name")))
  ignore(s.ensure(Key::field("others").push_idx(0)))
  s.clear_under(arr)
  assert_false(s.contains(arr.push_idx(0).push_field("name")))
  assert_false(s.contains(arr.push_idx(1).push_field("name")))
  assert_true(s.contains(Key::field("others").push_idx(0)))
}

///|
test "error map slots record and clear per cause" {
  let m = FieldMetaState::default_meta()
    .with_cause_errors(Change, Some(["c1"]))
    .with_cause_errors(Blur, Some(["b1"]))
  assert_eq(m.errors(), ["c1", "b1"]) // lifecycle order: Change before Blur
  assert_true(m.has_errors())
  assert_false(m.is_valid())
  let cleared = m.with_cause_errors(Change, None)
  assert_eq(cleared.errors(), ["b1"])
  let empty = cleared.with_cause_errors(Blur, None)
  assert_eq(empty.errors(), [])
  assert_true(empty.is_valid())
}

// the Server slot participates in the fixed lifecycle flatten order
// (upstream onServer); the slot exists even though v1 core does not run
// onServer validation itself

///|
test "error map: server slot records and flattens last" {
  let m = FieldMetaState::default_meta()
    .with_cause_errors(Change, Some(["c"]))
    .with_cause_errors(Server, Some(["s"]))
  assert_eq(m.error_map.get(Server), Some(["s"]))
  assert_eq(m.errors(), ["c", "s"]) // Server after Change (lifecycle order)
  let cleared = m.with_cause_errors(Server, None)
  assert_eq(cleared.errors(), ["c"])
}

///|
test "bump_array_version increments the array field's own meta" {
  let s = MetaStore::make()
  ignore(s.ensure(arr))
  s.bump_array_version(arr)
  s.bump_array_version(arr)
  match s.get(arr) {
    Some(m) => assert_eq(m.array_version, 2)
    None => fail("expected array meta")
  }
}

///|
test "store-level array rekeying matches upstream meta shifts" {
  // remove(0): friends.1.name error moves to friends.0.name; old slot gone
  let s = MetaStore::make()
  s.set(arr.push_idx(1).push_field("name"), err("too short"))
  s.set(arr.push_idx(2).push_field("name"), FieldMetaState::default_meta())
  s.remap_remove(arr, 0)
  match s.get(arr.push_idx(0).push_field("name")) {
    Some(m) => assert_eq(m.errors(), ["too short"])
    None => fail("expected shifted error at friends.0.name")
  }
  assert_true(s.contains(arr.push_idx(1).push_field("name")))
  assert_false(s.contains(arr.push_idx(2).push_field("name")))

  // insert(0): existing metas shift up; new slot 0 starts empty
  let s2 = MetaStore::make()
  s2.set(arr.push_idx(0).push_field("name"), err("e0"))
  s2.set(arr.push_idx(1).push_field("name"), err("e1"))
  s2.remap_insert(arr, 0)
  assert_false(s2.contains(arr.push_idx(0).push_field("name")))
  match s2.get(arr.push_idx(1).push_field("name")) {
    Some(m) => assert_eq(m.errors(), ["e0"])
    None => fail("expected e0 at slot 1")
  }
  match s2.get(arr.push_idx(2).push_field("name")) {
    Some(m) => assert_eq(m.errors(), ["e1"])
    None => fail("expected e1 at slot 2")
  }

  // swap(0, 2) exchanges whole subtrees
  let s3 = MetaStore::make()
  s3.set(arr.push_idx(0), err("a"))
  s3.set(arr.push_idx(2), err("c"))
  s3.remap_swap(arr, 0, 2)
  match s3.get(arr.push_idx(2)) {
    Some(m) => assert_eq(m.errors(), ["a"])
    None => fail("expected a at slot 2")
  }
  match s3.get(arr.push_idx(0)) {
    Some(m) => assert_eq(m.errors(), ["c"])
    None => fail("expected c at slot 0")
  }
}
