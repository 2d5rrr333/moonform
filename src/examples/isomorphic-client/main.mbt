// Isomorphic validation — the CLIENT side (js target): the shared
// validators mounted by the shared setup give real-time per-field feedback
// while the user types (writes go through the form; feedback reads from
// the field meta — the same slots a UI would render).
// Headless verification: `moon run src/examples/isomorphic-client --target js`.

///|
fn main {
  let form = @isomorphic.registration_form()
  let username_key = @isomorphic.registration_username_l().key
  let email_key = @isomorphic.registration_email_l().key
  let age_key = @isomorphic.registration_age_l().key
  // the user types invalid values: feedback appears per field, instantly
  form.set_value(@isomorphic.registration_username_l(), "ab")
  form.set_value(@isomorphic.registration_email_l(), "not-an-email")
  form.set_value(@isomorphic.registration_age_l(), 10)
  if !form.field_meta(username_key).has_errors() {
    abort("username feedback missing")
  }
  if !form.field_meta(email_key).has_errors() {
    abort("email feedback missing")
  }
  if !form.field_meta(age_key).has_errors() {
    abort("age feedback missing")
  }
  println("client: invalid input flagged per field in real time")
  // the user fixes everything
  form.set_value(@isomorphic.registration_username_l(), "moonbit")
  form.set_value(@isomorphic.registration_email_l(), "user@example.com")
  form.set_value(@isomorphic.registration_age_l(), 20)
  if form.field_meta(username_key).has_errors() ||
    form.field_meta(email_key).has_errors() ||
    form.field_meta(age_key).has_errors() {
    abort("stale feedback after fix")
  }
  println("client: fixed input clears feedback")
  // submission passes the same validators
  let submitted : ClientCounter = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => {
        submitted.n = submitted.n + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  if submitted.n != 1 || !form.is_submit_successful() {
    abort("submission unexpectedly blocked")
  }
  println("client: submission accepted")
  println("isomorphic client: all checks passed")
}

///|
priv struct ClientCounter {
  mut n : Int
}
