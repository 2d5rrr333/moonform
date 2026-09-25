// schema adapter: login-form parity with rules behavior (spec scenario:
// email/password schema validation feeds per-field error slots).

///|
struct Login {
  email : String
  password : String
} derive(Eq, ToJson, Debug)

///|
fn login_email_l() -> @core.Lens[Login, String] {
  @core.field("email", l => l.email, (l, e) => { ..l, email: e, })
}

///|
fn login_password_l() -> @core.Lens[Login, String] {
  @core.field("password", l => l.password, (l, p) => { ..l, password: p, })
}

///|
fn login_schema() -> @moonschema.Schema raise {
  @builder.object({
    "email": @builder.string().email(),
    "password": @builder.string().min_len(8),
  }).compile()
}

///|
fn ok_schema() -> @moonschema.Schema {
  login_schema() catch {
    _ => abort("schema compile failed")
  }
}

///|
test "schema adapter: per-field errors via JSON-Pointer paths" {
  let s = ok_schema()
  let form = @core.FormApi::make({ email: "not-an-email", password: "short", })
  let email = form.field(
    login_email_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "email",
      login_email_l(),
    ),
  )
  let password = form.field(
    login_password_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "password",
      login_password_l(),
    ),
  )
  email.mount()
  password.mount()
  email.set_value("not-an-email")
  password.set_value("short")
  assert_true(email.meta().has_errors())
  assert_true(password.meta().has_errors())
  // errors stay in their own field slots
  assert_false(email.meta().errors() == password.meta().errors())
}

///|
test "schema adapter: valid values produce no errors" {
  let s = ok_schema()
  let form = @core.FormApi::make({
    email: "root@example.com",
    password: "longenough1",
  })
  let email = form.field(
    login_email_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "email",
      login_email_l(),
    ),
  )
  let password = form.field(
    login_password_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "password",
      login_password_l(),
    ),
  )
  email.mount()
  password.mount()
  email.set_value("root@example.com")
  password.set_value("longenough1")
  assert_eq(email.meta().errors(), [])
  assert_eq(password.meta().errors(), [])
}

///|
test "schema adapter: empty email reaches the email slot" {
  let s = ok_schema()
  let v : @core.Validator[String, Login] = @schema.schema_field_validator(
    s,
    "email",
    login_email_l(),
  )
  let errs = @core.Validator::run(v, "", { email: "", password: "longenough1", })
  assert_true(errs.length() > 0)
}

///|
test "schema adapter: parity with rules-based validation" {
  let s = ok_schema()
  // rules validator: required + contains("@")
  let rules_email : @core.Validator[String, Login] = @rules.required().then(
    @rules.contains("@"),
  )
  let form = @core.FormApi::make({ email: "", password: "", })
  let email = form.field(
    login_email_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "email",
      login_email_l(),
    ),
  )
  email.mount()
  email.set_value("plainaddress")
  let schema_errs = email.meta().errors()
  assert_true(schema_errs.length() > 0) // schema flags invalid email
  // rules path: same judgment shape
  let rules_errs = @core.Validator::run(rules_email, "plainaddress", {
    email: "plainaddress",
    password: "",
  })
  assert_true(rules_errs.length() > 0)
}

// -- group validation --------------------------------------------------------

///|
struct SignupAccount {
  username : String
  email : String
} derive(Eq, ToJson, Debug)

///|
struct SignupForm {
  account : SignupAccount
  other : String
} derive(Eq, ToJson, Debug)

///|
fn signup_account_l() -> @core.Lens[SignupForm, SignupAccount] {
  @core.field("account", (v : SignupForm) => v.account, (v, a) => {
    ..v,
    account: a,
  })
}

///|
fn signup_username_l() -> @core.Lens[SignupForm, String] {
  signup_account_l().compose(
    @core.field("username", (a : SignupAccount) => a.username, (a, u) => {
      ..a,
      username: u,
    }),
  )
}

///|
fn signup_email_l() -> @core.Lens[SignupForm, String] {
  signup_account_l().compose(
    @core.field("email", (a : SignupAccount) => a.email, (a, e) => {
      ..a,
      email: e,
    }),
  )
}

///|
fn account_schema() -> @moonschema.Schema {
  @builder.object({
    "username": @builder.string().min_len(2),
    "email": @builder.string().email(),
  }).compile() catch {
    _ => abort("schema compile failed")
  }
}

///|
test "schema group validator: pointer errors distribute to child fields" {
  let s = account_schema()
  let form = @core.FormApi::make({
    account: { username: "x", email: "nope", },
    other: "",
  })
  let account = form.group(
    signup_account_l(),
    on_change_validate=@schema.schema_group_validator(s),
    on_submit_validate=@schema.schema_group_validator(s),
  )
  let username = form.field(signup_username_l())
  let email = form.field(signup_email_l())
  account.mount()
  username.mount()
  email.mount()
  // a change inside the group re-runs the schema over the whole group value
  username.set_value("x")
  assert_true(username.meta().has_errors()) // min_len error at "/username"
  assert_true(email.meta().has_errors()) // email-format error at "/email"
  assert_false(account.is_fields_valid())
  assert_true(account.is_group_valid()) // no group-level errors
  // fixing every field clears the distributed errors
  username.set_value("moonbit")
  email.set_value("moon@example.com")
  assert_true(account.is_fields_valid())
  assert_true(account.is_valid())
}

///|
struct FriendEntry {
  name : String
} derive(Eq, ToJson, Debug)

///|
struct RosterForm {
  friends : Array[FriendEntry]
} derive(Eq, ToJson, Debug)

///|
fn roster_friends_l() -> @core.Lens[RosterForm, Array[FriendEntry]] {
  @core.field("friends", (v : RosterForm) => v.friends, (_v, f) => {
    friends: f,
  })
}

///|
fn roster_friends_schema() -> @moonschema.Schema {
  @builder.array(@builder.object({ "name": @builder.string().min_len(2) }))
  .min_items(1)
  .compile() catch {
    _ => abort("schema compile failed")
  }
}

///|
test "schema group validator: array group errors are group-level" {
  let s = roster_friends_schema()
  let form = @core.FormApi::make({ friends: [], })
  let friends = form.group(
    roster_friends_l(),
    on_mount_validate=@schema.schema_group_validator(s),
    on_change_validate=@schema.schema_group_validator(s),
  )
  friends.mount()
  // minItems fires at the group root (empty instance path): group-level
  assert_true(friends.is_group_valid() == false)
  assert_true(friends.errors().length() > 0)
  // growing the array clears the group-level error
  form.push_value(roster_friends_l(), { name: "alice", })
  assert_true(friends.is_group_valid())
  assert_true(friends.is_valid())
}

///|
test "schema group validator: nested array pointers reach element fields" {
  let s = roster_friends_schema()
  let form = @core.FormApi::make({ friends: [{ name: "a", }, { name: "ok", }], })
  let friends = form.group(
    roster_friends_l(),
    on_change_validate=@schema.schema_group_validator(s),
  )
  let f0_name = form.field(
    @core.at(roster_friends_l(), 0).compose(
      @core.field("name", (f : FriendEntry) => f.name, (_f, n) => { name: n, }),
    ),
  )
  friends.mount()
  f0_name.mount()
  // "/0/name" distributes to the element field's key
  f0_name.set_value("a")
  assert_true(f0_name.meta().has_errors())
  assert_false(friends.is_fields_valid())
  f0_name.set_value("al")
  assert_true(friends.is_fields_valid())
}

///|
pub extend Login with Debug::{to_repr}

///|
pub extend Login with Eq::{not_equal, equal}

///|
pub extend Login with ToJson::{to_json}

///|
pub extend SignupAccount with Eq::{not_equal, equal}

///|
pub extend SignupAccount with ToJson::{to_json}

///|
pub extend SignupAccount with Debug::{to_repr}

///|
pub extend SignupForm with Eq::{not_equal, equal}

///|
pub extend SignupForm with ToJson::{to_json}

///|
pub extend SignupForm with Debug::{to_repr}

///|
pub extend FriendEntry with Eq::{not_equal, equal}

///|
pub extend FriendEntry with ToJson::{to_json}

///|
pub extend FriendEntry with Debug::{to_repr}

///|
pub extend RosterForm with Eq::{not_equal, equal}

///|
pub extend RosterForm with ToJson::{to_json}

///|
pub extend RosterForm with Debug::{to_repr}
