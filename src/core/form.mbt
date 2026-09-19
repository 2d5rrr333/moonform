///|
/// Lifecycle defaults overridable via `default_state` (upstream's partial
/// `defaultState`).
pub struct FormDefaultState[V] {
  values : V?
  submission_attempts : Int
  is_submitting : Bool
  is_submitted : Bool
  is_submit_successful : Bool
  is_validating : Bool
}

///|
pub fn[V] FormDefaultState::make() -> FormDefaultState[V] {
  {
    values: None,
    submission_attempts: 0,
    is_submitting: false,
    is_submitted: false,
    is_submit_successful: false,
    is_validating: false,
  }
}

///|
/// Internal record for a mounted field: how to apply the field's own
/// default value onto a form value, how to probe the field for dirtiness
/// against the form's current defaults, and its change listener. Closures
/// keep field typing at the registration site (no heterogeneous storage).
pub(all) struct FieldReg[V] {
  token : Int // identity of the owning field instance (stale-unmount guard)
  apply_default : ((V) -> V)?
  probe_dirty : (V, V) -> Bool
  on_change : ((V) -> Unit)?
  /// Change-cause validation dispatcher (runs the mounted field's
  /// configured onChange validators against the new value).
  validate_on_change : ((V) -> Unit)?
}

///|
/// The headless form state machine (upstream FormApi semantics).
/// Values live in the user's form value `V` (lens-addressed); metadata lives
/// in a structured-key store. Construct with `FormApi::make`.
pub struct FormApi[V] {
  mut default_values : V
  mut default_state : FormDefaultState[V]
  mut values : V
  mut submission_attempts : Int
  mut is_submitting : Bool
  mut is_submitted : Bool
  mut is_submit_successful : Bool
  mut is_validating : Bool
  meta : MetaStore
  field_regs : Map[Key, FieldReg[V]]
  subs : Subscriptions
  mut next_field_token : Int
  on_field_unmount : ((Key) -> Unit)?
  /// Injected time source for async validation / debounce (virtual in
  /// tests; real timers in host adapters). Absent = no async behavior.
  mut clock : Clock?
  /// Form-level submit error (upstream form errorMap.onSubmit).
  mut submit_error : String?
  /// Per-field onSubmit validator dispatch (mounted fields only).
  submit_validators : Map[Key, (V) -> Unit]
  /// Dependency watches (upstream onChangeListenTo): value-change of key K
  /// triggers re-validation of the fields registered under K, keyed by the
  /// listening field's key (unmount removes its watches wholesale).
  dep_watches : Map[Key, Map[Key, () -> Unit]]
}

///|
pub fn[V] FormApi::make(
  default_values : V,
  default_state? : FormDefaultState[V],
  on_field_unmount? : (Key) -> Unit,
) -> FormApi[V] {
  let ds = default_state.unwrap_or(FormDefaultState::make())
  {
    default_values,
    default_state: ds,
    values: ds.values.unwrap_or(default_values),
    submission_attempts: ds.submission_attempts,
    is_submitting: ds.is_submitting,
    is_submitted: ds.is_submitted,
    is_submit_successful: ds.is_submit_successful,
    is_validating: ds.is_validating,
    meta: MetaStore::make(),
    field_regs: Map([]),
    subs: Subscriptions::make(),
    next_field_token: 1,
    on_field_unmount,
    clock: None,
    submit_error: None,
    submit_validators: Map([]),
    dep_watches: Map([]),
  }
}

///|
/// Attach a Clock (time source) enabling async validation, debounce, and
/// other timing behavior. Returns the form for chaining.
pub fn[V] FormApi::with_clock(self : FormApi[V], clock : Clock) -> FormApi[V] {
  self.clock = Some(clock)
  self
}

// -- values ------------------------------------------------------------------

///|
/// The current form values.
pub fn[V] FormApi::values(self : FormApi[V]) -> V {
  self.values
}

///|
/// The current default values (upstream `options.defaultValues`).
pub fn[V] FormApi::default_values(self : FormApi[V]) -> V {
  self.default_values
}

///|
/// Read a field value through its accessor.
pub fn[V, A] FormApi::get_value(self : FormApi[V], lens : Lens[V, A]) -> A {
  lens.get(self.values)
}

///|
/// Set a field value (upstream `setFieldValue`): writes the value through the
/// accessor, marks the field touched and clears its onMount error slot
/// (unless `dont_update_meta`), then runs change listeners/validation.
pub fn[V, A] FormApi::set_value(
  self : FormApi[V],
  lens : Lens[V, A],
  value : A,
  dont_update_meta? : Bool,
  dont_run_listeners? : Bool,
  dont_validate? : Bool,
) -> Unit {
  let dont_meta = dont_update_meta.unwrap_or(false)
  if !dont_meta {
    self.meta.update(lens.key, m => {
      ..m,
      is_touched: true,
      is_dirty: true,
      error_map: m.error_map.set(Mount, None),
    })
  }
  self.values = lens.set(self.values, value)
  // change listener (upstream: triggerOnChangeListener), then notification
  if !dont_run_listeners.unwrap_or(false) {
    match self.field_regs.get(lens.key) {
      Some(reg) =>
        match reg.on_change {
          Some(f) => f(self.values)
          None => ()
        }
      None => ()
    }
  }
  self.subs.notify(lens.key, Value)
  // dependency watches (upstream onChangeListenTo): fields listening to
  // this key re-validate on its change
  match self.dep_watches.get(lens.key) {
    Some(watchers) =>
      for _owner, w in watchers {
        w()
      }
    None => ()
  }
  // change validation (upstream: validateField(field, 'change')), unless
  // suppressed — array ops orchestrate their own validation pass
  if !dont_validate.unwrap_or(false) {
    match self.field_regs.get(lens.key) {
      Some(reg) =>
        match reg.validate_on_change {
          Some(f) => f(self.values)
          None => ()
        }
      None => ()
    }
  }
}

// -- derived state -----------------------------------------------------------

///|
pub fn[V] FormApi::submission_attempts(self : FormApi[V]) -> Int {
  self.submission_attempts
}

///|
pub fn[V] FormApi::is_submitting(self : FormApi[V]) -> Bool {
  self.is_submitting
}

///|
pub fn[V] FormApi::is_submitted(self : FormApi[V]) -> Bool {
  self.is_submitted
}

///|
pub fn[V] FormApi::is_submit_successful(self : FormApi[V]) -> Bool {
  self.is_submit_successful
}

///|
pub fn[V] FormApi::is_validating(self : FormApi[V]) -> Bool {
  self.is_validating
}

///|
/// Any field's meta has `is_touched`.
pub fn[V] FormApi::is_touched(self : FormApi[V]) -> Bool {
  let mut touched = false
  for _k, m in self.meta.entries {
    if m.is_touched {
      touched = true
    }
  }
  touched
}

///|
/// Any field's meta has `is_blurred`.
pub fn[V] FormApi::is_blurred(self : FormApi[V]) -> Bool {
  let mut blurred = false
  for _k, m in self.meta.entries {
    if m.is_blurred {
      blurred = true
    }
  }
  blurred
}

///|
/// Any field is dirty. Mounted fields derive dirtiness by value comparison
/// against their effective default; fields written without a mounted
/// instance use their stored dirty flag (upstream `isDirty`).
pub fn[V] FormApi::is_dirty(self : FormApi[V]) -> Bool {
  let mut dirty = false
  for _k, reg in self.field_regs {
    if (reg.probe_dirty)(self.values, self.default_values) {
      dirty = true
    }
  }
  for k, m in self.meta.entries {
    if !self.field_regs.contains(k) && m.is_dirty {
      dirty = true
    }
  }
  dirty
}

///|
pub fn[V] FormApi::is_pristine(self : FormApi[V]) -> Bool {
  !self.is_dirty()
}

///|
/// Field metadata of the whole form (key -> meta).
pub fn[V] FormApi::meta_store(self : FormApi[V]) -> MetaStore {
  self.meta
}

///|
/// Metadata of one field (default meta when the field was never touched).
pub fn[V] FormApi::field_meta(self : FormApi[V], key : Key) -> FieldMetaState {
  self.meta.get_or_default(key)
}

///|
/// Does a meta entry exist for `key`? (upstream `fieldMeta[name] !== undefined`)
pub fn[V] FormApi::has_field_meta(self : FormApi[V], key : Key) -> Bool {
  self.meta.contains(key)
}

// -- update / reset ----------------------------------------------------------

///|
/// Replace form options (upstream `update`): swaps defaults; when the form is
/// untouched and the defaults changed, current values follow the new
/// defaults; lifecycle overlays the new default state.
pub fn[V : Eq] FormApi::update(
  self : FormApi[V],
  default_values? : V,
  default_state? : FormDefaultState[V],
) -> Unit {
  let touched = self.is_touched()
  match default_values {
    Some(dv) =>
      if !touched && !values_equal(dv, self.default_values) {
        self.default_values = dv
        self.values = dv
      } else {
        self.default_values = dv
      }
    None => ()
  }
  match default_state {
    Some(ds) => {
      self.default_state = ds
      if !touched {
        self.submission_attempts = ds.submission_attempts
        self.is_submitting = ds.is_submitting
        self.is_submitted = ds.is_submitted
        self.is_submit_successful = ds.is_submit_successful
        self.is_validating = ds.is_validating
        match ds.values {
          Some(v) => if !touched { self.values = v }
          None => ()
        }
      }
    }
    None => ()
  }
  self.subs.notify_all()
}

///|
/// Reset the form (upstream `reset`): every field meta entry returns to
/// default meta; values restore to `values` (if given, becoming the new
/// defaults unless `keep_default_values`), else to the current defaults with
/// every mounted field's own `defaultValue` applied on top; lifecycle
/// restores from the default state.
pub fn[V] FormApi::reset(
  self : FormApi[V],
  values? : V,
  keep_default_values? : Bool,
) -> Unit {
  // every existing meta entry resets to default meta (keys are kept)
  for k in self.meta.keys() {
    self.meta.set(k, FieldMetaState::default_meta())
  }
  let provided = values
  if provided is Some(v) && !keep_default_values.unwrap_or(false) {
    self.default_values = v
  }
  let mut next = match provided {
    Some(v) => v
    None =>
      // apply each mounted field's own default value onto the form defaults
      match self.default_state.values {
        Some(dv) => dv
        None => self.default_values
      }
  }
  if provided is None {
    for _k, reg in self.field_regs {
      match reg.apply_default {
        Some(f) => next = f(next)
        None => ()
      }
    }
  }
  self.values = next
  let ds = self.default_state
  self.submission_attempts = ds.submission_attempts
  self.is_submitting = ds.is_submitting
  self.is_submitted = ds.is_submitted
  self.is_submit_successful = ds.is_submit_successful
  self.is_validating = ds.is_validating
  self.subs.notify_all()
}

// -- field registration ------------------------------------------------------

///|
fn[V, A : Eq] FormApi::register_field(
  self : FormApi[V],
  lens : Lens[V, A],
  default_value : A?,
  on_change : ((A) -> Unit)?,
  validate_on_change : (V, A) -> Unit,
  validate_on_submit : (V, A) -> Unit,
) -> Int {
  let token = self.next_field_token
  self.next_field_token = token + 1
  let apply_default : ((V) -> V)? = match default_value {
    Some(d) => Some(v => lens.set(v, d))
    None => None
  }
  let probe_dirty : (V, V) -> Bool = (current, defaults) => {
    let eff_defaults = match default_value {
      Some(d) => lens.set(defaults, d)
      None => defaults
    }
    lens.get(current) != lens.get(eff_defaults)
  }
  let on_change_v : ((V) -> Unit)? = match on_change {
    Some(cb) => Some(values => cb(lens.get(values)))
    None => None
  }
  let validate_v : ((V) -> Unit)? = Some(values => {
    validate_on_change(values, lens.get(values))
  })
  self.submit_validators.set(lens.key, values => {
    validate_on_submit(values, lens.get(values))
  })
  self.field_regs.set(lens.key, {
    token,
    apply_default,
    probe_dirty,
    on_change: on_change_v,
    validate_on_change: validate_v,
  })
  token
}

///|
fn[V] FormApi::unregister_field(self : FormApi[V], key : Key) -> Unit {
  let _ = self.field_regs.remove(key)
}

///|
/// Delete a field from the form (upstream `deleteField`): removes its
/// registration and its meta entry plus every subfield's (keys under it).
/// Values are left in place — typed form values have no "absent field"
/// state, so value deletion does not apply (documented deviation).
pub fn[V] FormApi::delete_field(self : FormApi[V], key : Key) -> Unit {
  self.unregister_field(key)
  self.meta.remove(key)
  for k in self.meta.keys_under(key) {
    self.meta.remove(k)
  }
  self.subs.notify(key, Meta)
}

///|
/// Mark a field touched + blurred (upstream blur meta transition).
pub fn[V] FormApi::blur_field(self : FormApi[V], key : Key) -> Unit {
  self.meta.update(key, m => { ..m, is_touched: true, is_blurred: true, })
  self.subs.notify(key, Meta)
}

// -- subscriptions -----------------------------------------------------------

///|
/// Subscribe to any form change; returns a stable unsubscribe handle.
pub fn[V] FormApi::subscribe(self : FormApi[V], cb : () -> Unit) -> Int {
  self.subs.subscribe(cb)
}

///|
/// Subscribe to one field's changes (exact key), optionally filtered by
/// change kinds; returns a stable unsubscribe handle.
pub fn[V] FormApi::subscribe_field(
  self : FormApi[V],
  key : Key,
  kinds? : Array[ChangeKind],
  cb : () -> Unit,
) -> Int {
  match kinds {
    Some(ks) => self.subs.subscribe_field(key, kinds=ks, cb)
    None => self.subs.subscribe_field(key, cb)
  }
}

///|
/// Unsubscribe by handle (stable identity; missing handle is a no-op).
pub fn[V] FormApi::unsubscribe(self : FormApi[V], id : Int) -> Unit {
  self.subs.unsubscribe(id)
}

///|
/// Run `f` with change notifications coalesced: each subscriber fires at
/// most once at the end of the outermost batch.
pub fn[V] FormApi::batch(self : FormApi[V], f : () -> Unit) -> Unit {
  self.subs.batch(f)
}
