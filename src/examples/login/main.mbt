// Login form example: tiye/react adapter + moonschema validation.
// Headless verification run: `moon run src/examples/login --target js`.
// The React component version lives in README (component wiring uses the
// same FieldBridge via use_sync_external_store).

///|
struct LoginValues {
  email : String
  password : String
} derive(Eq, ToJson, Debug)

///|
struct Counter {
  mut n : Int
}

///|
fn email_l() -> @core.Lens[LoginValues, String] {
  @core.field("email", v => v.email, (v, e) => { ..v, email: e, })
}

///|
fn password_l() -> @core.Lens[LoginValues, String] {
  @core.field("password", v => v.password, (v, p) => { ..v, password: p, })
}

///|
fn login_schema() -> @moonschema.Schema raise {
  @builder.object({
    "email": @builder.string().email(),
    "password": @builder.string().min_len(8),
  }).compile()
}

///|
fn build_form() -> @core.FormApi[LoginValues] {
  let s = login_schema() catch { _ => abort("schema compile failed") }
  let form = @core.FormApi::make({ email: "", password: "", })
  // fields with schema validation feeding their slots
  let email = form.field(
    email_l(),
    on_change_validate=@formschema.schema_field_validator(s, "email", email_l()),
  )
  let password = form.field(
    password_l(),
    on_change_validate=@formschema.schema_field_validator(
      s,
      "password",
      password_l(),
    ),
  )
  email.mount()
  password.mount()
  form
}

// headless verification of the example flow (adapters spec scenario):
// input drives state updates; validation surfaces per-field errors;
// submission only passes on valid values.

///|
fn main raise {
  let form = build_form()
  let email = @formreact.FieldBridge::make(form, email_l())
  let password = @formreact.FieldBridge::make(form, password_l())
  email.attach()
  password.attach()
  // user types an invalid email and a short password
  email.set_value("not-an-email")
  password.set_value("short")
  assert_true(email.state().errors.length() > 0)
  assert_true(password.state().errors.length() > 0)
  // submit is blocked by field errors
  let invalid_called = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit_invalid: Some(_ => invalid_called.n = invalid_called.n + 1),
  })
  assert_eq(invalid_called.n, 1)
  // user fixes both
  email.set_value("root@example.com")
  password.set_value("longenough1")
  assert_eq(email.state().errors, [])
  assert_eq(password.state().errors, [])
  // submission succeeds now
  let submitted = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => {
        submitted.n = submitted.n + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  assert_eq(submitted.n, 1)
  assert_true(form.is_submit_successful())
  println("login example: all checks passed")
}
