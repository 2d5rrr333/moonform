// Isomorphic validation (shared definition): ONE set of field validators
// over ONE form value type, consumed by BOTH sides of the wire —
//
// - the js "client" (src/examples/isomorphic-client) mounts the validators
//   on a form for real-time per-field feedback;
// - the native "server" (src/examples/isomorphic-server) replays the same
//   validators through a fresh form instance as the final submission gate.
//
// core/rules are dependency-free and compile on all targets, so the
// definitions need zero changes to run on either side (no serialization
// boundary, no duplicated logic).

///|
pub(all) struct Registration {
  username : String
  email : String
  age : Int
  accept_terms : Bool
} derive(Eq, Debug)

///|
pub extend Registration with Debug::{to_repr}

///|
pub extend Registration with Eq::{not_equal, equal}

///|
pub fn registration_username_l() -> @core.Lens[Registration, String] {
  @core.field("username", (v : Registration) => v.username, (v, u) => {
    ..v,
    username: u,
  })
}

///|
pub fn registration_email_l() -> @core.Lens[Registration, String] {
  @core.field("email", (v : Registration) => v.email, (v, e) => {
    ..v,
    email: e,
  })
}

///|
pub fn registration_age_l() -> @core.Lens[Registration, Int] {
  @core.field("age", (v : Registration) => v.age, (v, a) => { ..v, age: a, })
}

///|
pub fn registration_terms_l() -> @core.Lens[Registration, Bool] {
  @core.field("accept_terms", (v : Registration) => v.accept_terms, (v, t) => {
    ..v,
    accept_terms: t,
  })
}

///|
/// The shared field validators — the single source of truth for both the
/// client's real-time feedback and the server's final gate.
pub fn registration_validators() -> RegistrationValidators {
  {
    username: @rules.required().then(@rules.min_length(3)),
    email: @rules.required().then(@rules.email()),
    age: @rules.min_int(13),
    terms: @rules.must_be_true(message="Terms must be accepted"),
  }
}

///|
pub struct RegistrationValidators {
  username : @core.Validator[String, Registration]
  email : @core.Validator[String, Registration]
  age : @core.Validator[Int, Registration]
  terms : @core.Validator[Bool, Registration]
}

///|
/// Mount a form with the shared validators (the common setup both sides
/// perform). Returns the form.
pub fn registration_form() -> @core.FormApi[Registration] {
  let v = registration_validators()
  let form = @core.FormApi::make({
    username: "",
    email: "",
    age: 0,
    accept_terms: false,
  })
  form.field(registration_username_l(), on_change_validate=v.username).mount()
  form.field(registration_email_l(), on_change_validate=v.email).mount()
  form.field(registration_age_l(), on_change_validate=v.age).mount()
  form.field(registration_terms_l(), on_change_validate=v.terms).mount()
  form
}

///|
/// The server-side final gate: replay the shared validators over a
/// submitted payload through a fresh form instance. Returns the per-field
/// errors (empty = accept).
pub fn server_review(payload : Registration) -> Array[(String, Array[String])] {
  let form = registration_form()
  form.set_value(registration_username_l(), payload.username)
  form.set_value(registration_email_l(), payload.email)
  form.set_value(registration_age_l(), payload.age)
  form.set_value(registration_terms_l(), payload.accept_terms)
  let out : Array[(String, Array[String])] = []
  let username_errs = form.field_meta(registration_username_l().key).errors()
  if username_errs.length() > 0 {
    out.push(("username", username_errs))
  }
  let email_errs = form.field_meta(registration_email_l().key).errors()
  if email_errs.length() > 0 {
    out.push(("email", email_errs))
  }
  let age_errs = form.field_meta(registration_age_l().key).errors()
  if age_errs.length() > 0 {
    out.push(("age", age_errs))
  }
  let terms_errs = form.field_meta(registration_terms_l().key).errors()
  if terms_errs.length() > 0 {
    out.push(("accept_terms", terms_errs))
  }
  out
}
