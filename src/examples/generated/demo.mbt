// The form flow over the generated accessors (same package: private
// generated fns are visible here).

///|
priv struct GenCounter {
  mut n : Int
}

///|
/// Drive a registration-style flow through the generated accessors:
/// validation errors surface per field, fixing them clears the errors, and
/// the submission succeeds. Returns true when every step held.
pub fn run_demo() -> Bool {
  let form = @core.FormApi::make({ nickname: "", age: 0, })
  let nickname = form.field(
    profile_nickname_l(),
    on_change_validate=@rules.required().then(@rules.min_length(3)),
  )
  let age = form.field(profile_age_l(), on_change_validate=@rules.min_int(13))
  nickname.mount()
  age.mount()
  // invalid input: errors surface through the generated accessors' fields
  nickname.set_value("ab")
  age.set_value(10)
  if !(nickname.meta().has_errors() && age.meta().has_errors()) {
    return false
  }
  // fix both: errors clear
  nickname.set_value("moonbit")
  age.set_value(20)
  if nickname.meta().has_errors() || age.meta().has_errors() {
    return false
  }
  // submission succeeds and the values read back through the accessors
  let submitted : GenCounter = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => {
        submitted.n = submitted.n + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  submitted.n == 1 &&
  form.is_submit_successful() &&
  form.get_value(profile_nickname_l()) == "moonbit" &&
  form.get_value(profile_age_l()) == 20
}
