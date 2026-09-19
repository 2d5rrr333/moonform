///|
/// The pluggable validator protocol (the "Resolver"). A resolver receives
/// the value being validated and the whole form value (for cross-field
/// logic) and returns error messages (empty list = valid). Synchronous
/// resolvers run inline; asynchronous ones are modelled as pending +
/// completion callback through the form's injected Clock (async phase).
pub struct Validator[A, V] {
  /// Field-level validator: receives the field value and the whole form.
  validate : (A, V) -> Array[String]
}

///|
/// Run the validator: value + form value → errors.
pub fn[A, V] Validator::run(
  self : Validator[A, V],
  value : A,
  form_value : V,
) -> Array[String] {
  (self.validate)(value, form_value)
}

///|
/// Build a validator from a simple value-only predicate.
pub fn[A, V] validator(f : (A) -> Array[String]) -> Validator[A, V] {
  { validate: (value, _form) => f(value), }
}

///|
/// Build a validator with access to the whole form value (cross-field).
pub fn[A, V] validator_with_form(
  f : (A, V) -> Array[String],
) -> Validator[A, V] {
  { validate: f, }
}

///|
/// Combine validators: all run in order; errors concatenate.
pub fn[A, V] Validator::then(
  self : Validator[A, V],
  next : Validator[A, V],
) -> Validator[A, V] {
  {
    validate: (value, form) => {
      (self.validate)(value, form) + (next.validate)(value, form)
    },
  }
}

///|
/// A field's validation wiring: one optional validator per trigger cause
/// (upstream validators.{onMount,onChange,onBlur,onSubmit}) plus the
/// asynchronous variants with debounce windows.
pub struct ValidationSpec[A, V] {
  on_mount : Validator[A, V]?
  on_change : Validator[A, V]?
  on_blur : Validator[A, V]?
  on_submit : Validator[A, V]?
  on_change_async : AsyncValidator[A, V]?
  on_blur_async : AsyncValidator[A, V]?
  /// Debounce window (ms) for the onChange async validator.
  on_change_async_debounce_ms : Int
  /// Debounce window (ms) for the onBlur async validator.
  on_blur_async_debounce_ms : Int
}

///|
pub fn[A, V] ValidationSpec::make() -> ValidationSpec[A, V] {
  {
    on_mount: None,
    on_change: None,
    on_blur: None,
    on_submit: None,
    on_change_async: None,
    on_blur_async: None,
    on_change_async_debounce_ms: 0,
    on_blur_async_debounce_ms: 0,
  }
}

///|
/// Run every configured sync validator for `cause`; returns None when no
/// validator is configured for the cause (absent slot stays absent).
pub fn[A, V] run_sync_validators(
  spec : ValidationSpec[A, V],
  cause : ValidationCause,
  value : A,
  form_value : V,
) -> Array[String]? {
  let v = match cause {
    Mount => spec.on_mount
    Change => spec.on_change
    Blur => spec.on_blur
    Submit => spec.on_submit
    Server => None
  }
  match v {
    Some(validator) => Some((validator.validate)(value, form_value))
    None => None
  }
}
