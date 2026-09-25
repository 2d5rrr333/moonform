///|
/// Field handle over one accessor (upstream FieldApi). Created from a form;
/// call `mount` to register the field (default value, listeners, validation
/// wiring in later phases) — unmounted fields are pure lens access.
pub struct FieldApi[V, A] {
  form : FormApi[V]
  lens : Lens[V, A]
  own_default : A?
  on_change_l : ((A) -> Unit)?
  on_blur_l : (() -> Unit)?
  on_mount_l : (() -> Unit)?
  on_unmount_l : (() -> Unit)?
  validation : ValidationSpec[A, V]
  /// Keys of fields whose changes should re-run this field's onChange
  /// validation (upstream onChangeListenTo).
  listen_to : Array[Key]
  mut mounted : Bool
  mut mount_token : Int?
  // async validation orchestration: monotonic run id (race guard) and the
  // pending debounce timer handle
  mut async_seq : Int
  mut async_validating : Bool
  mut async_timer : Int?
}

///|
/// Create a field handle (not yet mounted). Optional labeled parameters
/// mirror upstream FieldApi options: field-level `default` (defaultValue)
/// and the `listeners` callbacks.
pub fn[V, A] FormApi::field(
  self : FormApi[V],
  lens : Lens[V, A],
  default? : A,
  on_change? : (A) -> Unit,
  on_blur? : () -> Unit,
  on_mount? : () -> Unit,
  on_unmount? : () -> Unit,
  on_mount_validate? : Validator[A, V],
  on_change_validate? : Validator[A, V],
  on_blur_validate? : Validator[A, V],
  on_submit_validate? : Validator[A, V],
  on_change_async_validate? : AsyncValidator[A, V],
  on_blur_async_validate? : AsyncValidator[A, V],
  async_debounce_ms? : Int,
  on_change_async_debounce_ms? : Int,
  on_blur_async_debounce_ms? : Int,
  /// Keys of fields whose value changes re-run this field's onChange
  /// validation (upstream `onChangeListenTo`).
  listen_to? : Array[Key],
) -> FieldApi[V, A] {
  let common = async_debounce_ms.unwrap_or(0)
  {
    form: self,
    lens,
    own_default: default,
    on_change_l: on_change,
    on_blur_l: on_blur,
    on_mount_l: on_mount,
    on_unmount_l: on_unmount,
    validation: {
      on_mount: on_mount_validate,
      on_change: on_change_validate,
      on_blur: on_blur_validate,
      on_submit: on_submit_validate,
      on_change_async: on_change_async_validate,
      on_blur_async: on_blur_async_validate,
      on_change_async_debounce_ms: on_change_async_debounce_ms.unwrap_or(common),
      on_blur_async_debounce_ms: on_blur_async_debounce_ms.unwrap_or(common),
    },
    mounted: false,
    mount_token: None,
    async_seq: 0,
    async_validating: false,
    async_timer: None,
    listen_to: listen_to.unwrap_or([]),
  }
}

///|
/// Register the field: creates its meta entry, applies its own default on
/// form reset, wires its change listener (upstream `field.mount()`); runs
/// the onMount listener and onMount validation when configured.
pub fn[V, A : Eq] FieldApi::mount(self : FieldApi[V, A]) -> Unit {
  if self.mounted {
    return
  }
  self.mounted = true
  let noop_change : (V, A) -> Unit = (_, _) => ()
  let change_dispatch : (V, A) -> Unit = if self.validation.on_change is Some(_) {
    (form_value, _field_value) => {
      // run against the CURRENT values: the dispatcher fires after write
      self.run_validation_against(Change, form_value)
    }
  } else {
    noop_change
  }
  let submit_dispatch : (V, A) -> Unit = if self.validation.on_submit is Some(_) {
    (form_value, _field_value) => {
      self.run_validation_against(Submit, form_value)
    }
  } else {
    noop_change
  }
  let token = self.form.register_field(
    self.lens,
    self.own_default,
    self.on_change_l,
    change_dispatch,
    submit_dispatch,
  )
  self.mount_token = Some(token)
  // register dependency watches (upstream onChangeListenTo), owned by this
  // field's key so unmount removes them wholesale
  for dep in self.listen_to {
    let run = () => self.run_validation_against(Change, self.form.values)
    let watchers = match self.form.dep_watches.get(dep) {
      Some(ws) => ws
      None => {
        let ws : Map[Key, () -> Unit] = Map([])
        self.form.dep_watches.set(dep, ws)
        ws
      }
    }
    watchers.set(self.lens.key, run)
  }
  ignore(self.form.meta.ensure(self.lens.key))
  self.form.subs.notify(self.lens.key, Meta)
  match self.on_mount_l {
    Some(cb) => cb()
    None => ()
  }
  self.run_validation(Mount)
}

///|
/// Run this field's sync validators for `cause` against the current form
/// values and record the result in its errorMap slot (empty errors clear
/// the slot; no configured validator leaves the slot untouched). Notifies
/// meta subscribers when present.
pub fn[V, A] FieldApi::run_validation(
  self : FieldApi[V, A],
  cause : ValidationCause,
) -> Unit {
  self.run_validation_against(cause, self.form.values)
}

///|
/// Schedule the async validator for `cause` (ChangeAsync / BlurAsync) with
/// the configured debounce window. Re-scheduling cancels any pending
/// debounce timer and aborts in-flight results (race guard: only the
/// latest run's completion is applied). Requires the form to carry a
/// Clock (see `FormApi::with_clock`); without one, async validators
/// never run.
pub fn[V, A] FieldApi::schedule_async_validation(
  self : FieldApi[V, A],
  cause : AsyncCause,
) -> Unit {
  let (validator, debounce) = match cause {
    ChangeAsync =>
      (
        self.validation.on_change_async,
        self.validation.on_change_async_debounce_ms,
      )
    BlurAsync =>
      (self.validation.on_blur_async, self.validation.on_blur_async_debounce_ms)
  }
  let validator = match validator {
    Some(v) => v
    None => return
  }
  let clock = match self.form.clock {
    Some(c) => c
    None => return
  }
  // cancel pending debounce timer (upstream: clearTimeout on re-trigger)
  match self.async_timer {
    Some(id) => {
      clock.cancel(id)
      self.async_timer = None
    }
    None => ()
  }
  // in-flight runs are aborted by bumping the sequence
  self.async_seq = self.async_seq + 1
  let run = self.async_seq
  let form = self.form
  let key = self.lens.key
  let set_validating = (b : Bool) => {
    if self.async_validating != b {
      self.async_validating = b
      form.meta.update(key, m => { ..m, is_validating: b, })
      form.subs.notify(key, Meta)
    }
  }
  let launch = () => {
    self.async_timer = None
    match self.lens.try_get(form.values) {
      Some(value) => {
        set_validating(true)
        let form_value = form.values
        (validator.validate)(value, form_value, clock, errors => {
          if run == self.async_seq {
            // latest run: apply the result
            let slot : Array[String]? = if errors.length() > 0 {
              Some(errors)
            } else {
              None
            }
            let vcause : ValidationCause = match cause {
              ChangeAsync => Change
              BlurAsync => Blur
            }
            form.meta.update(key, m => m.with_cause_errors(vcause, slot))
            set_validating(false)
            form.subs.notify(key, Meta)
            // stale run: discarded (race guard)
          }
        })
      }
      None => () // stale array slot: skip the async run
    }
  }
  if debounce > 0 {
    self.async_timer = Some(clock.schedule(debounce, launch))
  } else {
    launch()
  }
}

///|
/// Abort any pending async work for this field: cancels the debounce
/// timer and invalidates in-flight runs (upstream unmount cleanup).
pub fn[V, A] FieldApi::abort_async_validation(self : FieldApi[V, A]) -> Unit {
  match self.form.clock {
    Some(clock) =>
      match self.async_timer {
        Some(id) => {
          clock.cancel(id)
          self.async_timer = None
        }
        None => ()
      }
    None => ()
  }
  self.async_seq = self.async_seq + 1 // invalidate in-flight completions
  if self.async_validating {
    self.async_validating = false
    self.form.meta.update(self.lens.key, m => { ..m, is_validating: false, })
    self.form.subs.notify(self.lens.key, Meta)
  }
}

///|
/// Like `run_validation`, but validates against a given form value (the
/// post-write value when dispatched from `set_value`). Stale array slots
/// (the field's index no longer exists in the value) are skipped.
pub fn[V, A] FieldApi::run_validation_against(
  self : FieldApi[V, A],
  cause : ValidationCause,
  form_value : V,
) -> Unit {
  match self.lens.try_get(form_value) {
    Some(value) =>
      match run_sync_validators(self.validation, cause, value, form_value) {
        Some(errors) => {
          let slot : Array[String]? = if errors.length() > 0 {
            Some(errors)
          } else {
            None
          }
          self.form.meta.update(self.lens.key, m => {
            m.with_cause_errors(cause, slot)
          })
          self.form.subs.notify(self.lens.key, Meta)
        }
        None => ()
      }
    None => () // stale array slot: nothing to validate
  }
}

///|
/// Unmount the field (upstream semantics): values are always preserved;
/// the field's meta keeps its interaction flags (touched/blurred/dirty) but
/// clears errors and the validating flag; the registration is removed. If a
/// newer instance owns the key, or the field was already deleted from the
/// form, this unmount is a no-op (no cleanup, no listener).
pub fn[V, A] FieldApi::unmount(self : FieldApi[V, A]) -> Unit {
  if !self.mounted {
    return
  }
  self.mounted = false
  self.abort_async_validation() // cancel debounce timers, invalidate runs
  let key = self.lens.key
  match self.form.field_regs.get(key) {
    Some(reg) => {
      let mine = match self.mount_token {
        Some(t) => t == reg.token
        None => false
      }
      if !mine {
        return // stale instance: a newer mount owns the registration
      }
      self.form.unregister_field(key)
      // remove this field's dependency watches (listen_to cleanup)
      for dep in self.listen_to {
        match self.form.dep_watches.get(dep) {
          Some(watchers) => {
            let _ = watchers.remove(key)
          }
          None => ()
        }
      }
      // reset meta to default, preserving interaction flags
      self.form.meta.update(key, m => {
        ..FieldMetaState::default_meta(),
        is_touched: m.is_touched,
        is_blurred: m.is_blurred,
        is_dirty: m.is_dirty,
        array_version: m.array_version,
      })
      self.form.subs.notify(key, Meta)
      match self.form.on_field_unmount {
        Some(cb) => cb(key)
        None => ()
      }
      match self.on_unmount_l {
        Some(cb) => cb()
        None => ()
      }
    }
    None => () // field was deleted from the form: no cleanup, no listener
  }
}

///|
/// This field's key.
pub fn[V, A] FieldApi::key(self : FieldApi[V, A]) -> Key {
  self.lens.key
}

///|
/// Current value of the field.
pub fn[V, A] FieldApi::value(self : FieldApi[V, A]) -> A {
  self.lens.get(self.form.values)
}

///|
/// The field's effective default: its own `default` if declared, else the
/// value in the form's current defaults.
pub fn[V, A] FieldApi::default_value(self : FieldApi[V, A]) -> A {
  match self.own_default {
    Some(d) => d
    None => self.lens.get(self.form.default_values)
  }
}

///|
/// Is the field dirty (value differs deeply from its effective default)?
/// Stale array slots (index gone from the value) are never dirty.
pub fn[V, A : Eq] FieldApi::is_dirty(self : FieldApi[V, A]) -> Bool {
  match
    (
      self.lens.try_get(self.form.values),
      self.lens.try_get(self.form.default_values),
    ) {
    (Some(cur), Some(def)) =>
      match self.own_default {
        Some(d) => cur != d
        None => cur != def
      }
    (None, None) => false
    _ => true
  }
}

///|
/// Set the value (upstream `setValue`): writes through the form, marks the
/// field touched, clears its onMount errors, runs the change listener, then
/// change validation (sync inline; async via debounce + race guard).
pub fn[V, A] FieldApi::set_value(
  self : FieldApi[V, A],
  value : A,
  dont_update_meta? : Bool,
  dont_run_listeners? : Bool,
  dont_validate? : Bool,
) -> Unit {
  self.form.set_value(
    self.lens,
    value,
    dont_update_meta=dont_update_meta.unwrap_or(false),
    dont_run_listeners=dont_run_listeners.unwrap_or(false),
    dont_validate=dont_validate.unwrap_or(false),
  )
  if !dont_validate.unwrap_or(false) &&
    self.validation.on_change_async is Some(_) {
    self.schedule_async_validation(ChangeAsync)
  }
}

///|
/// Value change from user input (upstream `handleChange`).
pub fn[V, A] FieldApi::handle_change(self : FieldApi[V, A], value : A) -> Unit {
  self.set_value(value)
}

///|
/// Blur the field: marks touched + blurred, runs the onBlur listener,
/// onBlur validation (sync inline; async via debounce + race guard).
pub fn[V, A] FieldApi::handle_blur(self : FieldApi[V, A]) -> Unit {
  self.form
  .meta_store()
  .update(self.lens.key, m => { ..m, is_touched: true, is_blurred: true, })
  self.form.subs.notify(self.lens.key, Meta)
  match self.on_blur_l {
    Some(cb) => cb()
    None => ()
  }
  self.run_validation(Blur)
  if self.validation.on_blur_async is Some(_) {
    self.schedule_async_validation(BlurAsync)
  }
}

///|
/// The field's metadata (default meta if the field was never touched).
pub fn[V, A] FieldApi::meta(self : FieldApi[V, A]) -> FieldMetaState {
  self.form.meta.get_or_default(self.lens.key)
}

///|
/// Reset the field (upstream `resetField`): the value returns to its
/// effective default (the field's own `default` if declared, else the form
/// defaults) and the field's meta entry resets to the default meta —
/// interaction flags and errors cleared.
pub fn[V, A] FieldApi::reset(self : FieldApi[V, A]) -> Unit {
  self.form.values = (self.lens.set)(self.form.values, self.default_value())
  self.form.meta.set(self.lens.key, FieldMetaState::default_meta())
  self.form.subs.notify(self.lens.key, Value)
  self.form.subs.notify(self.lens.key, Meta)
}
