///|
/// Asynchronous validator protocol: validate with a completion callback.
/// The validator performs its asynchronous work against the injected
/// `Clock` (virtual in tests, real timers in host adapters) and reports
/// its errors exactly once via `done`.
pub struct AsyncValidator[A, V] {
  validate : (A, V, Clock, (Array[String]) -> Unit) -> Unit
}

///|
/// Build an async validator from a value-only async function.
pub fn[A, V] async_validator(
  f : (A, Clock, (Array[String]) -> Unit) -> Unit,
) -> AsyncValidator[A, V] {
  { validate: (value, _form, clock, done) => f(value, clock, done), }
}

///|
/// Build an async validator with access to the whole form value.
pub fn[A, V] async_validator_with_form(
  f : (A, V, Clock, (Array[String]) -> Unit) -> Unit,
) -> AsyncValidator[A, V] {
  { validate: f, }
}

///|
/// Async trigger causes a field can be configured for.
pub enum AsyncCause {
  ChangeAsync
  BlurAsync
} derive(Eq, Debug)

///|
pub extend AsyncCause with Debug::{to_repr}

///|
pub extend AsyncCause with Eq::{not_equal, equal}
