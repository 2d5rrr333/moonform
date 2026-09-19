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
    on_change_validate=schema_field_validator(s, "email", login_email_l()),
  )
  let password = form.field(
    login_password_l(),
    on_change_validate=schema_field_validator(s, "password", login_password_l()),
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
    on_change_validate=schema_field_validator(s, "email", login_email_l()),
  )
  let password = form.field(
    login_password_l(),
    on_change_validate=schema_field_validator(s, "password", login_password_l()),
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
  let v : @core.Validator[String, Login] = schema_field_validator(
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
    on_change_validate=schema_field_validator(s, "email", login_email_l()),
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
