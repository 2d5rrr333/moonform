///|
/// What the onSubmit handler reports back: success, a domain error, or a
/// prevented submission (upstream preventDefault). Asynchronous work is
/// expressed with a completion callback driven by the form's Clock.
pub enum SubmitResult {
  Ok
  Err(String)
  /// upstream preventDefault: submission cancelled; submit count not
  /// incremented by the submit success path.
  Prevented
}

///|
/// The submit handler: receives current values; reports via `done`.
pub struct SubmitHandler[V] {
  handler : (V, (SubmitResult) -> Unit) -> Unit
}

///|
/// Constructors for SubmitResult (blackbox callers cannot construct
/// read-only enum values cross-package).
pub fn SubmitResult::ok() -> SubmitResult {
  Ok
}

///|
pub fn SubmitResult::err(message : String) -> SubmitResult {
  Err(message)
}

///|
pub fn SubmitResult::prevented() -> SubmitResult {
  Prevented
}

///|
pub fn[V] submit_handler(
  f : (V, (SubmitResult) -> Unit) -> Unit,
) -> SubmitHandler[V] {
  { handler: f, }
}

///|
pub(all) struct SubmitOptions[V] {
  on_submit : SubmitHandler[V]?
  on_submit_invalid : ((V) -> Unit)?
  /// Domain error recorded when onSubmit reports Err.
  on_submit_error : ((String) -> Unit)?
}

///|
pub fn[V] SubmitOptions::make() -> SubmitOptions[V] {
  { on_submit: None, on_submit_invalid: None, on_submit_error: None, }
}

///|
/// Submission control block: form-level submit error (upstream form error
/// via `form.state.errorMap.onSubmit`).
fn[V] FormApi::set_submit_error(self : FormApi[V], error : String?) -> Unit {
  self.submit_error = error
}

///|
/// Are all recorded fields error-free? (upstream isFieldsValid)
pub fn[V] FormApi::is_valid_fields(self : FormApi[V]) -> Bool {
  for _k, m in self.meta.entries {
    if m.has_errors() {
      return false
    }
  }
  true
}

///|
/// Can the form be submitted? (upstream canSubmit): yes while untouched
/// and never attempted, or when not validating/submitting and valid.
pub fn[V] FormApi::can_submit(self : FormApi[V]) -> Bool {
  let never_touched = !self.is_touched() && self.submission_attempts == 0
  if never_touched {
    for _k, m in self.meta.entries {
      if m.error_map.get(Mount) is Some(_) {
        return false // onMount errors block a first attempt
      }
    }
    return true
  }
  !self.is_validating_any() &&
  !self.is_submitting &&
  self.is_valid_fields() &&
  !(self.submit_error is Some(_))
}

///|
fn[V] FormApi::is_validating_any(self : FormApi[V]) -> Bool {
  for _k, m in self.meta.entries {
    if m.is_validating {
      return true
    }
  }
  false
}

///|
/// Begin a submission (upstream `handleSubmit`, synchronous orchestration):
/// 1. isSubmitted=false, attempts+1, isSubmitSuccessful=false
/// 2. untouched mounted fields become touched
/// 3. canSubmit=false (first attempt) → onSubmitInvalid, done
/// 4. isSubmitting=true; run every mounted field's onSubmit validators
/// 5. field errors → onSubmitInvalid, done
/// 6. run on_submit listeners; invoke the submit handler
/// 7. Ok → isSubmitted+isSubmitSuccessful, attempts unchanged upstream —
///    (moonform: submit_count == submission_attempts throughout);
///    Err → error recorded; Preven(via handler) → attempts not incremented
///
/// The submit handler may complete synchronously (call `done` before
/// returning) or asynchronously through the form's Clock. Returns the
/// outcome synchronously when known, or the pending submission finishes
/// via the clock (tests tick the clock then inspect state).
pub fn[V] FormApi::handle_submit(
  self : FormApi[V],
  submit_options? : SubmitOptions[V],
) -> Unit {
  let opts = submit_options.unwrap_or(SubmitOptions::make())
  self.is_submitted = false
  self.submission_attempts = self.submission_attempts + 1
  self.is_submit_successful = false
  self.set_submit_error(None)
  // untouched mounted fields become touched
  let keys = self.meta.keys()
  for k in keys {
    self.meta.update(k, m => {
      if m.is_touched {
        m
      } else {
        { ..m, is_touched: true, }
      }
    })
  }
  if !self.can_submit() && self.submission_attempts <= 1 {
    match opts.on_submit_invalid {
      Some(f) => f(self.values)
      None => ()
    }
    return
  }
  self.is_submitting = true
  self.subs.notify_all()
  // field-level onSubmit validation across mounted fields
  for k in self.field_regs.keys() {
    match self.submit_validators.get(k) {
      Some(f) => f(self.values)
      None => ()
    }
  }
  if !self.is_valid_fields() {
    self.is_submitting = false
    match opts.on_submit_invalid {
      Some(f) => f(self.values)
      None => ()
    }
    self.subs.notify_all()
    return
  }
  // form-level submit listener then handler
  match opts.on_submit {
    Some(handler) => {
      let finish = (result : SubmitResult) => {
        match result {
          Ok => {
            self.is_submitting = false
            self.is_submitted = true
            self.is_submit_successful = true
          }
          Err(msg) => {
            self.is_submitting = false
            self.is_submit_successful = false
            self.set_submit_error(Some(msg))
          }
          Prevented => {
            self.is_submitting = false
            // upstream: submit count not incremented — revert
            self.submission_attempts = self.submission_attempts - 1
          }
        }
        self.subs.notify_all()
      }
      (handler.handler)(self.values, finish)
      // synchronous handlers have already called finish; async ones
      // complete via the clock
    }
    None => {
      // no handler: treat as successful no-op submission
      self.is_submitting = false
      self.is_submitted = true
      self.is_submit_successful = true
      self.subs.notify_all()
    }
  }
}

///|
/// Form-level submission error, if any (upstream form errorMap.onSubmit).
pub fn[V] FormApi::submit_error(self : FormApi[V]) -> String? {
  self.submit_error
}
