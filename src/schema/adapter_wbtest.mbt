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

// -- RFC 6901 escapes (0.8.7 audit) -------------------------------------------

///|
test "pointer_to_key: ~1 and ~0 unescape to / and ~" {
  assert_eq(pointer_to_key("/a~1b").unwrap().render(), "a/b")
  assert_eq(pointer_to_key("/a~0b").unwrap().render(), "a~b")
  assert_eq(pointer_to_key("/a~01").unwrap().render(), "a~1")
  // escapes unescape per segment; segments stay dot-separated in the render
  assert_eq(pointer_to_key("/x~1y/z~0w").unwrap().render(), "x/y.z~w")
}

///|
test "pointer_to_key: non-canonical digit segments are object keys" {
  // leading zeros: object keys per RFC 6901 (moonschema's own pointer
  // parser rejects them as indices)
  assert_eq(pointer_to_key("/01").unwrap().render(), "01")
  // 9+ digits (phone numbers): never wrapped into a bogus Int index
  assert_eq(pointer_to_key("/13800138000").unwrap().render(), "13800138000")
  // canonical indices still map to Idx (Field and Idx render alike —
  // distinguish by key equality)
  assert_true(pointer_to_key("/0").unwrap() == @core.Key::idx(0))
  assert_true(pointer_to_key("/12").unwrap() == @core.Key::idx(12))
  assert_true(pointer_to_key("/01").unwrap() != @core.Key::idx(1))
}

///|
test "quoted_property: supplementary-plane characters between the quotes" {
  // the property name contains an emoji: extracting by UTF-16 offsets
  // would garble it; the codepoint-array build keeps it whole
  let m = "must have required property \"na🙂me\" [required @ #/required]"
  assert_eq(quoted_property(m).unwrap(), "na🙂me")
}

///|
test "escape_pointer_token: mirrors the engine's token escaping" {
  assert_eq(escape_pointer_token("a/b"), "a~1b")
  assert_eq(escape_pointer_token("a~b"), "a~0b")
  assert_eq(escape_pointer_token("a/b~c"), "a~1b~0c")
  assert_eq(escape_pointer_token("plain"), "plain")
}
