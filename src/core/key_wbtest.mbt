// Key construction, rendering, prefix matching, and array-remap pure logic.
// (whitebox: exercises package-internal remap functions)

///|
test "key constructors and render" {
  assert_eq(Key::root().render(), "")
  assert_eq(Key::field("email").render(), "email")
  assert_eq(Key::idx(3).render(), "3")
  assert_eq(
    Key::field("friends").push_idx(1).push_field("name").render(),
    "friends.1.name",
  )
  assert_eq(
    Key::field("a").push_idx(0).push_field("b").push_idx(2).render(),
    "a.0.b.2",
  )
}

///|
test "concat produces a new key without aliasing" {
  let k1 = Key::field("user")
  let k2 = Key::field("email")
  let k3 = k1.concat(k2)
  assert_eq(k1.length(), 1)
  assert_eq(k2.length(), 1)
  assert_eq(k3.length(), 2)
  assert_eq(k3.render(), "user.email")
  // repeated concat is stable
  assert_eq(k1.concat(k2), Key::field("user").push_field("email"))
}

///|
test "key equality is structural" {
  assert_eq(
    Key::field("user").push_field("email"),
    Key::from_segs([Field("user"), Field("email")]),
  )
  assert_true(Key::idx(1) != Key::idx(2))
  assert_true(Key::field("1") != Key::idx(1)) // segment kind matters
}

///|
test "strip_prefix whole-segment semantics" {
  let k = Key::field("friends").push_idx(0).push_field("name")
  // exact prefix → rest
  match k.strip_prefix(Key::field("friends")) {
    Some(r) => assert_eq(r.render(), "0.name")
    None => fail("expected prefix match")
  }
  // full match → empty rest
  match k.strip_prefix(Key::field("friends").push_idx(0).push_field("name")) {
    Some(r) => assert_eq(r.length(), 0)
    None => fail("expected full match")
  }
  // sibling trap: string-prefix but different segment
  assert_true(k.strip_prefix(Key::field("friend")) is None)
  assert_true(k.strip_prefix(Key::field("friends_alt")) is None)
  // longer prefix than key
  assert_true(Key::field("friends").strip_prefix(k) is None)
  // index segment mismatch
  assert_true(k.strip_prefix(Key::field("friends").push_idx(1)) is None)
}

///|
test "has_prefix" {
  let k = Key::field("user").push_field("email")
  assert_true(k.has_prefix(Key::field("user")))
  assert_true(k.has_prefix(Key::root()))
  assert_false(k.has_prefix(Key::field("emails")))
}

// ---------------------------------------------------------------------------
// remap: remove
// ---------------------------------------------------------------------------

///|
fn mkstore(entries : Array[(Key, Int)]) -> Map[Key, Int] {
  let m : Map[Key, Int] = Map([])
  for pair in entries {
    let (k, v) = pair
    m.set(k, v)
  }
  m
}

///|
fn geti(m : Map[Key, Int], k : Key) -> Int {
  match m.get(k) {
    Some(v) => v
    None => abort("missing key \{k.render()}")
  }
}

///|
let friends : Key = Key::field("friends")

///|
test "remap remove shifts sibling meta down and drops removed slot" {
  let store = mkstore([
    (friends.push_idx(1).push_field("name"), 11),
    (friends.push_idx(2).push_field("name"), 12),
    (friends, 99),
    (Key::field("friends_alt").push_idx(0), 50),
    (Key::field("user").push_field("email"), 60),
  ])
  let out = key_remap_remove(store, friends, 0)
  assert_eq(geti(out, friends.push_idx(0).push_field("name")), 11)
  assert_eq(geti(out, friends.push_idx(1).push_field("name")), 12)
  assert_true(out.get(friends.push_idx(2).push_field("name")) is None)
  assert_eq(geti(out, friends), 99) // array field itself kept
  assert_eq(geti(out, Key::field("friends_alt").push_idx(0)), 50) // trap kept
  assert_eq(geti(out, Key::field("user").push_field("email")), 60)
}

///|
test "remap remove only touches indices after prefix (nested keys follow)" {
  let store = mkstore([
    (friends.push_idx(1).push_field("tags").push_idx(0), 7),
    (friends.push_idx(1).push_field("tags").push_idx(3), 8),
  ])
  let out = key_remap_remove(store, friends, 0)
  assert_eq(geti(out, friends.push_idx(0).push_field("tags").push_idx(0)), 7)
  assert_eq(geti(out, friends.push_idx(0).push_field("tags").push_idx(3)), 8)
}

///|
test "remap remove on nested array prefix leaves other arrays untouched" {
  let prefix = friends.push_idx(1).push_field("tags")
  let store = mkstore([
    (prefix.push_idx(0), 1),
    (prefix.push_idx(1), 2),
    (friends.push_idx(0).push_field("tags").push_idx(0), 3),
  ])
  let out = key_remap_remove(store, prefix, 0)
  assert_eq(geti(out, prefix.push_idx(0)), 2)
  assert_true(out.get(prefix.push_idx(1)) is None)
  assert_eq(geti(out, friends.push_idx(0).push_field("tags").push_idx(0)), 3)
}

///|
test "remap remove with out-of-range index is a structural no-op" {
  let store = mkstore([(friends.push_idx(0), 1), (friends.push_idx(1), 2)])
  let out = key_remap_remove(store, friends, 5)
  assert_eq(geti(out, friends.push_idx(0)), 1)
  assert_eq(geti(out, friends.push_idx(1)), 2)
}

///|
test "remap remove last index drops it" {
  let store = mkstore([(friends.push_idx(2).push_field("name"), 12)])
  let out = key_remap_remove(store, friends, 2)
  assert_true(out.get(friends.push_idx(2).push_field("name")) is None)
  assert_eq(out.length(), 0)
}

// ---------------------------------------------------------------------------
// remap: insert
// ---------------------------------------------------------------------------

///|
test "remap insert shifts slots at and above i up" {
  let store = mkstore([
    (friends.push_idx(0).push_field("name"), 10),
    (friends.push_idx(1).push_field("name"), 11),
  ])
  let out = key_remap_insert(store, friends, 0)
  assert_true(out.get(friends.push_idx(0).push_field("name")) is None)
  assert_eq(geti(out, friends.push_idx(1).push_field("name")), 10)
  assert_eq(geti(out, friends.push_idx(2).push_field("name")), 11)
}

///|
test "remap insert in the middle" {
  let store = mkstore([
    (friends.push_idx(0), 10),
    (friends.push_idx(1), 11),
    (friends.push_idx(2), 12),
  ])
  let out = key_remap_insert(store, friends, 1)
  assert_eq(geti(out, friends.push_idx(0)), 10)
  assert_true(out.get(friends.push_idx(1)) is None)
  assert_eq(geti(out, friends.push_idx(2)), 11)
  assert_eq(geti(out, friends.push_idx(3)), 12)
}

///|
test "remap insert at end (push) leaves existing slots" {
  let store = mkstore([(friends.push_idx(0), 10), (friends.push_idx(1), 11)])
  let out = key_remap_insert(store, friends, 2)
  assert_eq(geti(out, friends.push_idx(0)), 10)
  assert_eq(geti(out, friends.push_idx(1)), 11)
  assert_true(out.get(friends.push_idx(2)) is None)
}

// ---------------------------------------------------------------------------
// remap: swap
// ---------------------------------------------------------------------------

///|
test "remap swap exchanges subtrees including nested keys" {
  let store = mkstore([
    (friends.push_idx(0).push_field("name"), 10),
    (friends.push_idx(0).push_field("tags").push_idx(0), 13),
    (friends.push_idx(2).push_field("name"), 12),
    (friends.push_idx(1).push_field("name"), 11),
  ])
  let out = key_remap_swap(store, friends, 0, 2)
  assert_eq(geti(out, friends.push_idx(2).push_field("name")), 10)
  assert_eq(geti(out, friends.push_idx(2).push_field("tags").push_idx(0)), 13)
  assert_eq(geti(out, friends.push_idx(0).push_field("name")), 12)
  assert_eq(geti(out, friends.push_idx(1).push_field("name")), 11) // bystander
}

///|
test "remap swap with same index is a no-op" {
  let store = mkstore([(friends.push_idx(0), 10), (friends.push_idx(1), 11)])
  let out = key_remap_swap(store, friends, 1, 1)
  assert_eq(geti(out, friends.push_idx(0)), 10)
  assert_eq(geti(out, friends.push_idx(1)), 11)
}

// ---------------------------------------------------------------------------
// remap: move
// ---------------------------------------------------------------------------

///|
test "remap move forward rotates the range" {
  // move(0, 2): 0→2, 1→0, 2→1, 3 stays
  let store = mkstore([
    (friends.push_idx(0), 10),
    (friends.push_idx(1), 11),
    (friends.push_idx(2), 12),
    (friends.push_idx(3), 13),
  ])
  let out = key_remap_move(store, friends, 0, 2)
  assert_eq(geti(out, friends.push_idx(0)), 11)
  assert_eq(geti(out, friends.push_idx(1)), 12)
  assert_eq(geti(out, friends.push_idx(2)), 10)
  assert_eq(geti(out, friends.push_idx(3)), 13)
}

///|
test "remap move backward rotates the range" {
  // move(2, 0): 2→0, 0→1, 1→2, 3 stays
  let store = mkstore([
    (friends.push_idx(0), 10),
    (friends.push_idx(1), 11),
    (friends.push_idx(2), 12),
    (friends.push_idx(3), 13),
  ])
  let out = key_remap_move(store, friends, 2, 0)
  assert_eq(geti(out, friends.push_idx(0)), 12)
  assert_eq(geti(out, friends.push_idx(1)), 10)
  assert_eq(geti(out, friends.push_idx(2)), 11)
  assert_eq(geti(out, friends.push_idx(3)), 13)
}

///|
test "remap move with from == to is a no-op" {
  let store = mkstore([(friends.push_idx(0), 10), (friends.push_idx(1), 11)])
  let out = key_remap_move(store, friends, 1, 1)
  assert_eq(geti(out, friends.push_idx(0)), 10)
  assert_eq(geti(out, friends.push_idx(1)), 11)
}

///|
test "remap move preserves keys outside the range and nested keys" {
  let store = mkstore([
    (friends.push_idx(0).push_field("name"), 10),
    (friends.push_idx(1).push_field("name"), 11),
    (friends.push_idx(5).push_field("name"), 15),
  ])
  let out = key_remap_move(store, friends, 1, 0)
  assert_eq(geti(out, friends.push_idx(0).push_field("name")), 11)
  assert_eq(geti(out, friends.push_idx(1).push_field("name")), 10)
  assert_eq(geti(out, friends.push_idx(5).push_field("name")), 15)
}
