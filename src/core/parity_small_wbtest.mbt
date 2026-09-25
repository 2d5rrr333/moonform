// Remaining small-spec translations, form-core@1.33.5:
// - fieldMeta.spec.ts (mount-state visibility of field metadata)
// - formOptions.spec.ts (default values flow into form state)
// transform.spec.ts is exempted (mergeForm/SSR machinery — see
// upstream/SOURCES.md); its core assertion (errors seeded into form state
// reach the field meta) is covered by the "mount: pre-existing meta entry
// survives mount" test in field_wbtest.mbt.

///|
struct Deep {
  user : NestedUser
} derive(Eq, Debug)

///|
struct NestedUser {
  first : String
  last : String
} derive(Eq, Debug)

///|
fn deep_user_l() -> Lens[Deep, NestedUser] {
  field("user", d => d.user, (_d, u) => { user: u, })
}

///|
fn nested_first_l() -> Lens[NestedUser, String] {
  field("first", u => u.first, (u, f) => { ..u, first: f, })
}

///|
fn nested_last_l() -> Lens[NestedUser, String] {
  field("last", u => u.last, (u, l) => { ..u, last: l, })
}

///|
struct Names {
  first : String
  last : String
} derive(Eq, Debug)

///|
fn names_first_l() -> Lens[Names, String] {
  field("firstName", n => n.first, (n, f) => { ..n, first: f, })
}

///|
struct Creds {
  username : String
  password : String
} derive(Eq, Debug)

///|
fn creds_username_l() -> Lens[Creds, String] {
  field("username", c => c.username, (c, u) => { ..c, username: u, })
}

// upstream fieldMeta.spec: "should return undefined for unmounted fields"

///|
test "fieldMeta: unmounted fields have no meta entry" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  assert_false(form.has_field_meta(name_l().key))
  assert_false(form.has_field_meta(surname_l().key))
}

// upstream fieldMeta.spec: "should have defined fieldMeta after field is
// mounted" (default meta: valid, untouched, not dirty)

///|
test "fieldMeta: mounted field has default meta" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  assert_true(form.has_field_meta(name_l().key))
  let m = form.field_meta(name_l().key)
  assert_true(m.is_valid())
  assert_false(m.is_touched)
  assert_false(m.is_dirty)
}

// upstream fieldMeta.spec: "should handle nested field paths"

///|
test "fieldMeta: nested paths via composed lens" {
  let defaults : Deep = { user: { first: "", last: "", }, }
  let form = FormApi::make(defaults)
  let first = form.field(deep_user_l().compose(nested_first_l()))
  assert_false(form.has_field_meta(deep_user_l().compose(nested_first_l()).key))
  assert_false(form.has_field_meta(deep_user_l().compose(nested_last_l()).key))
  first.mount()
  assert_true(form.has_field_meta(deep_user_l().compose(nested_first_l()).key))
  assert_false(form.has_field_meta(deep_user_l().compose(nested_last_l()).key))
}

// upstream fieldMeta.spec: "should handle array fields"

///|
test "fieldMeta: array element fields via index lens" {
  let form = FormApi::make({ names: ["a", "b"], })
  let f0 = form.field(at(names_l(), 0))
  assert_false(form.has_field_meta(at(names_l(), 0).key))
  assert_false(form.has_field_meta(at(names_l(), 1).key))
  f0.mount()
  assert_true(form.has_field_meta(at(names_l(), 0).key))
  assert_false(form.has_field_meta(at(names_l(), 1).key))
}

// upstream fieldMeta.spec: "should preserve fieldMeta after unmounting and
// remounting"

///|
test "fieldMeta: meta preserved across unmount (interaction flags)" {
  let form = FormApi::make({ name: "", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  field.set_value("test")
  assert_true(form.field_meta(name_l().key).is_touched)
  assert_true(form.field_meta(name_l().key).is_dirty)
  field.unmount()
  // interaction flags survive unmount
  assert_true(form.field_meta(name_l().key).is_touched)
}

// upstream formOptions.spec: "should allow default values to be set"

///|
test "formOptions: default values flow into form state" {
  let defaults : Names = { first: "FirstName", last: "LastName", }
  let form = FormApi::make(defaults)
  assert_eq(form.values().first, "FirstName")
  assert_eq(form.values().last, "LastName")
  assert_eq(form.get_value(names_first_l()), "FirstName")
}

// standardSchemaValidator.spec rewrite (Resolver protocol behavior parity):
// a schema-style validator (judges values, reports per-field errors)
// feeds the field's error slot through the standard protocol.

///|
test "resolver parity: schema-style validator feeds field errors" {
  let schema_style : Validator[String, Creds] = validator_with_form((
    username,
    creds,
  ) => {
    if username.length() < 3 {
      ["username: must be at least 3 characters"]
    } else if creds.password == username {
      ["username: must differ from password"]
    } else {
      []
    }
  })
  let form = FormApi::make({ username: "ab", password: "xy", })
  let username = form.field(creds_username_l(), on_change_validate=schema_style)
  username.mount()
  username.set_value("ab")
  assert_eq(username.meta().errors(), [
    "username: must be at least 3 characters",
  ])
  username.set_value("secret")
  assert_eq(username.meta().errors(), [])
}

///|
pub extend Creds with Debug::{to_repr}

///|
pub extend Creds with Eq::{not_equal, equal}

///|
pub extend Deep with Debug::{to_repr}

///|
pub extend Deep with Eq::{not_equal, equal}

///|
pub extend Names with Debug::{to_repr}

///|
pub extend Names with Eq::{not_equal, equal}

///|
pub extend NestedUser with Debug::{to_repr}

///|
pub extend NestedUser with Eq::{not_equal, equal}
