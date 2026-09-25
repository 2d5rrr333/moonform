// Isomorphic shared-definition behavior (blackbox): the server-side gate
// replays the shared validators; the same definitions that drive the
// client's real-time feedback reject hostile payloads and accept corrected
// ones. These tests run on js/wasm/native — the isomorphism claim itself.

///|
test "isomorphic: server gate rejects a hostile payload on every field" {
  let hostile : @isomorphic.Registration = {
    username: "x",
    email: "nope",
    age: 9,
    accept_terms: false,
  }
  let rejected = @isomorphic.server_review(hostile)
  assert_eq(rejected.length(), 4)
  let fields = rejected.map(pair => {
    let (name, _errs) = pair
    name
  })
  assert_true(fields.contains("username"))
  assert_true(fields.contains("email"))
  assert_true(fields.contains("age"))
  assert_true(fields.contains("accept_terms"))
}

///|
test "isomorphic: server gate accepts a corrected payload" {
  let good : @isomorphic.Registration = {
    username: "moonbit",
    email: "user@example.com",
    age: 20,
    accept_terms: true,
  }
  assert_eq(@isomorphic.server_review(good).length(), 0)
}

///|
test "isomorphic: the same validators flag partial invalidity" {
  let partial : @isomorphic.Registration = {
    username: "moonbit",
    email: "nope",
    age: 20,
    accept_terms: true,
  }
  let rejected = @isomorphic.server_review(partial)
  assert_eq(rejected.length(), 1)
  let (field, errs) = rejected[0]
  assert_eq(field, "email")
  assert_true(errs.length() > 0)
}
