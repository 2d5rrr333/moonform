// FormBridge: the React-facing bridge for the whole form — the form
// counterpart of FieldBridge/GroupBridge. The snapshot derives from
// form-level lifecycle state (submit lifecycle, overall field validity,
// touch flags, form-level submit error), so the bridge subscribes to every
// notification (whole-form subscription). Snapshot discipline matches the
// other bridges: identity-stable between core notifications
// (use_sync_external_store contract).

///|
/// A stable whole-form snapshot for React rendering: rebuilt when the core
/// notifies, identity-stable between notifications.
pub struct FormState {
  is_submitting : Bool
  is_submitted : Bool
  is_submit_successful : Bool
  is_validating : Bool
  /// Are all recorded fields error-free? (upstream isFieldsValid)
  is_valid_fields : Bool
  can_submit : Bool
  is_touched : Bool
  is_blurred : Bool
  submission_attempts : Int
  /// Form-level submit error (upstream form errorMap.onSubmit).
  submit_error : String?
  /// Snapshot revision — increments on every core notification.
  rev : Int
} derive(Debug)

///|
/// Bridge between the whole core form and React. Create once per component
/// instance, drive it via `use_form` / `use_form_handle`, and wire `submit`
/// into the form's submit handler — the natural driver for submit-button
/// state (disabled/spinner while submitting, form-level error display).
pub struct FormBridge[V] {
  form : @core.FormApi[V]
  mut snapshot : FormState
  mut sub_id : Int?
  /// React's re-render callback from use_sync_external_store; set by
  /// `attach_with_notify`, invoked on every core notification.
  mut notify : (() -> Unit)?
}

///|
pub fn[V] FormBridge::make(form : @core.FormApi[V]) -> FormBridge[V] {
  { form, snapshot: build_form_snapshot(form, 0), sub_id: None, notify: None, }
}

///|
fn[V] build_form_snapshot(form : @core.FormApi[V], rev : Int) -> FormState {
  {
    is_submitting: form.is_submitting(),
    is_submitted: form.is_submitted(),
    is_submit_successful: form.is_submit_successful(),
    is_validating: form.is_validating(),
    is_valid_fields: form.is_valid_fields(),
    can_submit: form.can_submit(),
    is_touched: form.is_touched(),
    is_blurred: form.is_blurred(),
    submission_attempts: form.submission_attempts(),
    submit_error: form.submit_error(),
    rev,
  }
}

///|
/// Refresh the snapshot from the core (bumps rev) and notify React that
/// the store changed (schedules a re-render). Called on every core
/// notification.
pub fn[V] FormBridge::refresh(self : FormBridge[V]) -> Unit {
  let next_rev = self.snapshot.rev + 1
  self.snapshot = build_form_snapshot(self.form, next_rev)
  match self.notify {
    Some(cb) => cb()
    None => ()
  }
}

///|
/// Current snapshot (Object.is-stable until refresh).
pub fn[V] FormBridge::state(self : FormBridge[V]) -> FormState {
  self.snapshot
}

///|
/// The underlying form handle (value access, reset, update).
pub fn[V] FormBridge::form(self : FormBridge[V]) -> @core.FormApi[V] {
  self.form
}

///|
/// Subscribe the bridge to every core notification WITHOUT a React notify
/// callback (headless mode; refreshes snapshots only). For React wiring
/// prefer `attach_with_notify`.
pub fn[V] FormBridge::attach(self : FormBridge[V]) -> Unit {
  match self.sub_id {
    Some(_) => () // already attached
    None => self.sub_id = Some(self.form.subscribe(() => self.refresh()))
  }
}

///|
/// Subscribe with React's notify callback (use_sync_external_store
/// contract): every core change refreshes the snapshot AND schedules a
/// React re-render.
pub fn[V] FormBridge::attach_with_notify(
  self : FormBridge[V],
  notify : () -> Unit,
) -> Unit {
  self.notify = Some(notify)
  self.attach()
}

///|
/// Unsubscribe (component unmount).
pub fn[V] FormBridge::detach(self : FormBridge[V]) -> Unit {
  match self.sub_id {
    Some(id) => {
      self.form.unsubscribe(id)
      self.sub_id = None
      self.notify = None
    }
    None => ()
  }
}

///|
/// Trigger the form's submission (submit-button wiring): validates every
/// mounted field, then invokes the submit handler; the snapshot reflects
/// the submit lifecycle (is_submitting in flight, is_submitted /
/// submit_error on completion).
pub fn[V] FormBridge::submit(
  self : FormBridge[V],
  submit_options? : @core.SubmitOptions[V],
) -> Unit {
  let opts = submit_options.unwrap_or(@core.SubmitOptions::make())
  self.form.handle_submit(submit_options=opts)
}

///|
pub extend FormState with Debug::{to_repr}
