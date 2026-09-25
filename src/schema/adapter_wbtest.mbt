// schema group validator internals (whitebox): JSON-Pointer parsing and
// quoted-property extraction.

///|
test "pointer_to_key: field, nested, and index segments" {
  assert_eq(pointer_to_key("/username").unwrap().render(), "username")
  assert_eq(pointer_to_key("/items/0/name").unwrap().render(), "items.0.name")
  assert_eq(pointer_to_key("/0").unwrap().render(), "0")
  assert_eq(
    pointer_to_key("/friends/12/nick").unwrap().render(),
    "friends.12.nick",
  )
}

///|
test "pointer_to_key: root and slash-only paths are None" {
  assert_true(pointer_to_key("") is None)
  assert_true(pointer_to_key("/") is None)
}

///|
test "quoted_property: extracts the first quoted name" {
  let m = "(root): must have required property \"username\" [required @ #/required]"
  assert_eq(quoted_property(m).unwrap(), "username")
  assert_true(quoted_property("no quotes here") is None)
  // unterminated quote
  assert_true(quoted_property("only \"start") is None)
}
