// FormGroupApi (upstream FormGroupApi, form-core@1.33.5): group-scoped
// validation, error distribution to child fields, and group submission that
// never touches the parent form's submission state. A group is addressed by
// a Lens into the form value — the group's structured key is the prefix of
// every child field key, so "fields under the group" is a prefix query.

///|
/// Internal record for a mounted group (mirrors FieldReg): closures keep the
/// group's typing at the registration site (no heterogeneous storage).
pub(all) struct GroupReg[V] {
  token : Int // identity of the owning group instance (stale-unmount guard)
  /// Field-change dispatch: run the group's onChange listener, its change
  /// validation (with error distribution), and the async variant.
  dispatch_change : (V) -> Unit
  /// Form-reset dispatch: clear the group's own submission/error state.
  reset : () -> Unit
}

///|
/// One distributed field-error entry: the field's key RELATIVE to the group
/// (e.g. `Key::field("name")` inside a group at `step1` addresses
/// `step1.name`).
pub struct GroupFieldError {
  key : Key
  errors : Array[String]
} derive(Eq, Debug)

///|
/// Result of a group validator: errors for the group itself plus errors to
/// distribute to child fields (upstream: a string return is a group error; a
/// `{group, fields}` return is both; a plain `fields` map distributes only).
pub struct GroupValidationResult {
  group_errors : Array[String]
  field_errors : Array[GroupFieldError]
} derive(Eq, Debug)

///|
/// A clean result (upstream returning undefined).
pub fn GroupValidationResult::valid() -> GroupValidationResult {
  { group_errors: [], field_errors: [], }
}

///|
/// Group-level error only (upstream returning a string).
pub fn GroupValidationResult::group_error(
  message : String,
) -> GroupValidationResult {
  { group_errors: [message], field_errors: [], }
}

///|
/// Field errors only (upstream returning `{fields}`); entries are
/// (relative key, message) pairs.
pub fn GroupValidationResult::fields(
  entries : Array[(Key, String)],
) -> GroupValidationResult {
  let field_errors : Array[GroupFieldError] = []
  for pair in entries {
    let (k, msg) = pair
    field_errors.push({ key: k, errors: [msg], })
  }
  { group_errors: [], field_errors, }
}

///|
/// Group-level error plus distributed field errors (upstream
/// `{group, fields}`).
pub fn GroupValidationResult::group_and_fields(
  message : String,
  entries : Array[(Key, String)],
) -> GroupValidationResult {
  { ..GroupValidationResult::fields(entries), group_errors: [message], }
}

///|
/// General construction: group-level errors plus per-field error lists
/// (aggregating adapters — e.g. the schema adapter — build results this
/// way; entries are (relative key, messages) pairs).
pub fn GroupValidationResult::make(
  group_errors : Array[String],
  field_errors : Array[(Key, Array[String])],
) -> GroupValidationResult {
  let fields : Array[GroupFieldError] = []
  for pair in field_errors {
    let (k, msgs) = pair
    fields.push({ key: k, errors: msgs.copy(), })
  }
  { group_errors: group_errors.copy(), field_errors: fields, }
}

///|
/// Group validator protocol: receives the group value and the whole form
/// value; returns the group's validation result (empty = valid).
pub struct GroupValidator[G, V] {
  validate : (G, V) -> GroupValidationResult
}

///|
/// Build a group validator with access to the whole form value.
pub fn[G, V] group_validator(
  f : (G, V) -> GroupValidationResult,
) -> GroupValidator[G, V] {
  { validate: f, }
}

///|
/// Build a group validator judging the group value only.
pub fn[G, V] group_validator_value(
  f : (G) -> GroupValidationResult,
) -> GroupValidator[G, V] {
  { validate: (g, _form) => f(g), }
}

///|
/// Asynchronous group validator: performs its work against the injected
/// `Clock` and reports its result exactly once via `done`.
pub struct AsyncGroupValidator[G, V] {
  validate : (G, V, Clock, (GroupValidationResult) -> Unit) -> Unit
}

///|
pub fn[G, V] async_group_validator(
  f : (G, V, Clock, (GroupValidationResult) -> Unit) -> Unit,
) -> AsyncGroupValidator[G, V] {
  { validate: f, }
}

///|
/// A group's validation wiring (upstream FormGroupApi `validators`).
pub struct GroupValidationSpec[G, V] {
  on_mount : GroupValidator[G, V]?
  on_change : GroupValidator[G, V]?
  on_submit : GroupValidator[G, V]?
  on_change_async : AsyncGroupValidator[G, V]?
  /// Debounce window (ms) for the async onChange validator.
  on_change_async_debounce_ms : Int
}

///|
pub fn[G, V] GroupValidationSpec::make() -> GroupValidationSpec[G, V] {
  {
    on_mount: None,
    on_change: None,
    on_submit: None,
    on_change_async: None,
    on_change_async_debounce_ms: 0,
  }
}

///|
/// Group handle over one accessor (upstream FormGroupApi): group-scoped
/// validators with error distribution to child fields, group listeners, and
/// a group-scoped submission that never touches the parent form's submission
/// state. Create via `FormApi::group`, then `mount`.
pub struct FormGroupApi[V, G] {
  form : FormApi[V]
  lens : Lens[V, G]
  on_mount_l : ((G) -> Unit)?
  on_change_l : ((G) -> Unit)?
  on_unmount_l : ((G) -> Unit)?
  validation : GroupValidationSpec[G, V]
  mut mounted : Bool
  mut mount_token : Int?
  /// Group-level error slots (upstream `state.meta.errorMap`).
  mut error_map : ErrorMap
  /// Group-scoped submission counter — never the parent form's.
  mut submission_attempts : Int
  /// Set when the group value is written through `set_value`.
  mut is_touched : Bool
  mut is_validating : Bool
  // async validation orchestration: monotonic run id (race guard) and the
  // pending debounce timer handle
  mut async_seq : Int
  mut async_timer : Int?
  /// (cause, relative key) pairs this group last distributed — a clean
  /// re-validation for the cause clears those slots (upstream single-slot
  /// replace semantics).
  mut owned_field_errors : Array[(ValidationCause, Key)]
}

///|
/// Create a group handle (not yet mounted). Optional labeled parameters
/// mirror upstream FormGroupApi options: the `listeners` callbacks and the
/// `validators` per cause, plus the async onChange variant with its debounce
/// window.
pub fn[V, G] FormApi::group(
  self : FormApi[V],
  lens : Lens[V, G],
  on_mount? : (G) -> Unit,
  on_change? : (G) -> Unit,
  on_unmount? : (G) -> Unit,
  on_mount_validate? : GroupValidator[G, V],
  on_change_validate? : GroupValidator[G, V],
  on_submit_validate? : GroupValidator[G, V],
  on_change_async_validate? : AsyncGroupValidator[G, V],
  on_change_async_debounce_ms? : Int,
) -> FormGroupApi[V, G] {
  {
    form: self,
    lens,
    on_mount_l: on_mount,
    on_change_l: on_change,
    on_unmount_l: on_unmount,
    validation: {
      on_mount: on_mount_validate,
      on_change: on_change_validate,
      on_submit: on_submit_validate,
      on_change_async: on_change_async_validate,
      on_change_async_debounce_ms: on_change_async_debounce_ms.unwrap_or(0),
    },
    mounted: false,
    mount_token: None,
    error_map: ErrorMap::empty(),
    submission_attempts: 0,
    is_touched: false,
    is_validating: false,
    async_seq: 0,
    async_timer: None,
    owned_field_errors: [],
  }
}

///|
/// Register the group (upstream `group.mount()`): wires the form-level
/// change dispatch, runs the onMount listener, then the group's onMount
/// validation with error distribution. Distribution reaches fields that are
/// not mounted yet — their errors surface once they mount.
pub fn[V, G] FormGroupApi::mount(self : FormGroupApi[V, G]) -> Unit {
  if self.mounted {
    return
  }
  self.mounted = true
  let token = self.form.next_group_token
  self.form.next_group_token = token + 1
  let dispatch_change = (values : V) => {
    match self.on_change_l {
      Some(cb) => cb((self.lens.get)(values))
      None => ()
    }
    // a change inside the group supersedes the group's onMount judgment —
    // mirrors field-level set_value clearing Mount errors on write
    if self.error_map.get(Mount) is Some(_) {
      self.error_map = self.error_map.set(Mount, None)
    }
    self.run_validation_against(Change, values)
    if self.validation.on_change_async is Some(_) {
      self.schedule_async_validation()
    }
  }
  let reset = () => {
    self.error_map = ErrorMap::empty()
    self.submission_attempts = 0
    self.is_touched = false
    self.owned_field_errors = []
  }
  self.form.group_regs.set(self.lens.key, { token, dispatch_change, reset, })
  self.mount_token = Some(token)
  match self.on_mount_l {
    Some(cb) => cb((self.lens.get)(self.form.values))
    None => ()
  }
  self.run_validation(Mount)
}

///|
/// Unmount the group (upstream semantics): aborts in-flight async
/// validation, clears the group's own error state and its distributed field
/// errors, removes the registration, and runs the onUnmount listener. A
/// newer instance owning the key makes this a no-op (stale-unmount guard).
pub fn[V, G] FormGroupApi::unmount(self : FormGroupApi[V, G]) -> Unit {
  if !self.mounted {
    return
  }
  self.mounted = false
  self.abort_async_validation()
  match self.form.group_regs.get(self.lens.key) {
    Some(reg) => {
      let mine = match self.mount_token {
        Some(t) => t == reg.token
        None => false
      }
      if !mine {
        return // stale instance: a newer mount owns the registration
      }
      let _ = self.form.group_regs.remove(self.lens.key)
      self.clear_owned_field_errors()
      self.error_map = ErrorMap::empty()
      match self.on_unmount_l {
        Some(cb) => cb((self.lens.get)(self.form.values))
        None => ()
      }
    }
    None => ()
  }
}

///|
/// The group's current value.
pub fn[V, G] FormGroupApi::value(self : FormGroupApi[V, G]) -> G {
  (self.lens.get)(self.form.values)
}

///|
/// Write the whole group value (upstream `group.setValue`): marks the group
/// touched, runs the group's onChange listener and change validation (with
/// distribution, plus the async variant), and fires ONLY the form-level
/// onChangeGroup listener — the form-level onChange listener does not fire
/// for group writes.
pub fn[V, G] FormGroupApi::set_value(
  self : FormGroupApi[V, G],
  value : G,
) -> Unit {
  self.form.values = (self.lens.set)(self.form.values, value)
  self.is_touched = true
  // a group write supersedes the group's onMount judgment (mirrors field
  // set_value clearing Mount errors on write)
  if self.error_map.get(Mount) is Some(_) {
    self.error_map = self.error_map.set(Mount, None)
  }
  match self.on_change_l {
    Some(cb) => cb(value)
    None => ()
  }
  self.run_validation(Change)
  if self.validation.on_change_async is Some(_) {
    self.schedule_async_validation()
  }
  self.form.subs.notify(self.lens.key, Value)
  self.form.fire_on_change_group(self.lens.key)
}

///|
/// The group's key (the prefix of every child field key).
pub fn[V, G] FormGroupApi::key(self : FormGroupApi[V, G]) -> Key {
  self.lens.key
}

///|
/// Run the group's validators for `cause` against the current form values:
/// the sync validator sets the group's own slot and distributes field
/// errors; for `Change` the async variant is scheduled with its debounce
/// window (requires the form to carry a Clock).
pub fn[V, G] FormGroupApi::validate(
  self : FormGroupApi[V, G],
  cause : ValidationCause,
) -> Unit {
  self.run_validation_against(cause, self.form.values)
  if cause == Change && self.validation.on_change_async is Some(_) {
    self.schedule_async_validation()
  }
}

///|
fn[V, G] FormGroupApi::run_validation(
  self : FormGroupApi[V, G],
  cause : ValidationCause,
) -> Unit {
  self.run_validation_against(cause, self.form.values)
}

///|
fn[V, G] FormGroupApi::run_validation_against(
  self : FormGroupApi[V, G],
  cause : ValidationCause,
  form_value : V,
) -> Unit {
  let validator = match cause {
    Mount => self.validation.on_mount
    Change => self.validation.on_change
    Submit => self.validation.on_submit
    _ => None
  }
  match validator {
    Some(v) => {
      let result = (v.validate)((self.lens.get)(form_value), form_value)
      self.apply_result(cause, result)
    }
    None => ()
  }
}

///|
/// Apply a validation result: replace the group's own error slot, clear
/// previously distributed slots for this cause that the result no longer
/// lists, then distribute the new field errors. Slots are replaced, never
/// merged — overlapping writers on the same field cannot duplicate errors
/// (upstream single-slot semantics).
fn[V, G] FormGroupApi::apply_result(
  self : FormGroupApi[V, G],
  cause : ValidationCause,
  result : GroupValidationResult,
) -> Unit {
  let slot : Array[String]? = if result.group_errors.length() > 0 {
    Some(result.group_errors.copy())
  } else {
    None
  }
  self.error_map = self.error_map.set(cause, slot)
  // distribute the result's field errors (relative keys -> full keys)
  let fresh : Array[Key] = []
  for fe in result.field_errors {
    let field_slot : Array[String]? = if fe.errors.length() > 0 {
      Some(fe.errors.copy())
    } else {
      None
    }
    let full = self.lens.key.concat(fe.key)
    self.form.meta.update(full, m => m.with_cause_errors(cause, field_slot))
    self.form.subs.notify(full, Meta)
    fresh.push(fe.key)
  }
  // clear stale distributed slots for this cause, keep the rest
  let kept : Array[(ValidationCause, Key)] = []
  for pair in self.owned_field_errors {
    let (c, k) = pair
    let re_listed = key_listed(fresh, k)
    if c == cause && !re_listed {
      let full = self.lens.key.concat(k)
      self.form.meta.update(full, m => m.with_cause_errors(cause, None))
      self.form.subs.notify(full, Meta)
    } else {
      kept.push(pair)
    }
  }
  // register ownership of the freshly distributed keys
  for fk in fresh {
    if !owned_listed(kept, cause, fk) {
      kept.push((cause, fk))
    }
  }
  self.owned_field_errors = kept
  self.form.subs.notify(self.lens.key, Meta)
}

///|
fn key_listed(keys : Array[Key], k : Key) -> Bool {
  let mut hit = false
  for x in keys {
    if x == k {
      hit = true
    }
  }
  hit
}

///|
fn owned_listed(
  owned : Array[(ValidationCause, Key)],
  cause : ValidationCause,
  k : Key,
) -> Bool {
  let mut hit = false
  for pair in owned {
    let (c, x) = pair
    if c == cause && x == k {
      hit = true
    }
  }
  hit
}

///|
/// Clear every field slot this group distributed (unmount cleanup).
fn[V, G] FormGroupApi::clear_owned_field_errors(
  self : FormGroupApi[V, G],
) -> Unit {
  for pair in self.owned_field_errors {
    let (c, k) = pair
    let full = self.lens.key.concat(k)
    self.form.meta.update(full, m => m.with_cause_errors(c, None))
    self.form.subs.notify(full, Meta)
  }
  self.owned_field_errors = []
}

///|
/// Schedule the group's async onChange validator with the configured
/// debounce window. Re-scheduling cancels the pending debounce timer and
/// invalidates in-flight results (race guard: only the latest run's
/// completion is applied). Requires the form to carry a Clock; without one,
/// async validators never run.
pub fn[V, G] FormGroupApi::schedule_async_validation(
  self : FormGroupApi[V, G],
) -> Unit {
  let validator = match self.validation.on_change_async {
    Some(v) => v
    None => return
  }
  let clock = match self.form.clock {
    Some(c) => c
    None => return
  }
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
  let launch = () => {
    self.async_timer = None
    self.set_validating(true)
    let form_value = form.values
    let group_value = (self.lens.get)(form_value)
    (validator.validate)(group_value, form_value, clock, result => {
      if run == self.async_seq {
        // latest run: apply the result (stale runs are discarded)
        self.apply_result(Change, result)
        self.set_validating(false)
      }
    })
  }
  let debounce = self.validation.on_change_async_debounce_ms
  if debounce > 0 {
    self.async_timer = Some(clock.schedule(debounce, launch))
  } else {
    launch()
  }
}

///|
fn[V, G] FormGroupApi::set_validating(
  self : FormGroupApi[V, G],
  b : Bool,
) -> Unit {
  if self.is_validating != b {
    self.is_validating = b
    self.form.subs.notify(self.lens.key, Meta)
  }
}

///|
/// Abort any pending async work for this group: cancels the debounce timer
/// and invalidates in-flight completions (upstream unmount cleanup / abort
/// signal semantics).
pub fn[V, G] FormGroupApi::abort_async_validation(
  self : FormGroupApi[V, G],
) -> Unit {
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
  self.set_validating(false)
}

// -- derived state -----------------------------------------------------------

///|
/// Flattened group-level errors in fixed lifecycle order — the group's own
/// slots only; child field errors are read from the fields.
pub fn[V, G] FormGroupApi::errors(self : FormGroupApi[V, G]) -> Array[String] {
  self.error_map.flatten()
}

///|
/// Group-level error slot for one cause (upstream `state.meta.errorMap`).
pub fn[V, G] FormGroupApi::error_for_cause(
  self : FormGroupApi[V, G],
  cause : ValidationCause,
) -> Array[String]? {
  self.error_map.get(cause)
}

///|
/// Any field under the group (or the group value itself) has been touched.
pub fn[V, G] FormGroupApi::is_touched(self : FormGroupApi[V, G]) -> Bool {
  if self.is_touched {
    return true
  }
  let p = self.lens.key
  let plen = p.segs.length()
  for k, m in self.form.meta.entries {
    // strictly under the group key (the group's own meta entry is not a
    // child field; group writes set the group flag above)
    if k.segs.length() > plen && k.has_prefix(p) && m.is_touched {
      return true
    }
  }
  false
}

///|
/// Are all child fields error-free? (upstream `state.meta.isFieldsValid` —
/// includes errors distributed to fields that are not mounted yet).
pub fn[V, G] FormGroupApi::is_fields_valid(self : FormGroupApi[V, G]) -> Bool {
  let p = self.lens.key
  for k, m in self.form.meta.entries {
    // prefix-inclusive: the group key's own meta entry may hold field
    // errors when a field is mounted at the group's lens
    if k.has_prefix(p) && m.has_errors() {
      return false
    }
  }
  true
}

///|
/// Is the group's own validation clean? (upstream `state.meta.isGroupValid`)
pub fn[V, G] FormGroupApi::is_group_valid(self : FormGroupApi[V, G]) -> Bool {
  !self.error_map.has_errors()
}

///|
/// Both the group and its child fields are error-free (upstream isValid).
pub fn[V, G] FormGroupApi::is_valid(self : FormGroupApi[V, G]) -> Bool {
  self.is_group_valid() && self.is_fields_valid()
}

///|
/// Can the group be submitted? (upstream group canSubmit): yes while
/// untouched and never attempted (with no onMount errors), or when not
/// validating and fully valid.
pub fn[V, G] FormGroupApi::can_submit(self : FormGroupApi[V, G]) -> Bool {
  let never_touched = !self.is_touched() && self.submission_attempts == 0
  if never_touched {
    if self.error_map.get(Mount) is Some(_) {
      return false
    }
    let p = self.lens.key
    for k, m in self.form.meta.entries {
      if k.has_prefix(p) && m.error_map.get(Mount) is Some(_) {
        return false
      }
    }
    return true
  }
  !self.is_validating && self.is_valid()
}

///|
/// This group's submission attempts — the parent form's counter is never
/// touched by group submissions.
pub fn[V, G] FormGroupApi::submission_attempts(
  self : FormGroupApi[V, G],
) -> Int {
  self.submission_attempts
}

///|
pub fn[V, G] FormGroupApi::is_validating(self : FormGroupApi[V, G]) -> Bool {
  self.is_validating
}

// -- group submission --------------------------------------------------------

///|
/// Group-scoped submission (upstream `group.handleSubmit`): validates the
/// group's child fields (their onSubmit validators) and the group's own
/// onSubmit validator, then reports via `on_group_submit` /
/// `on_group_submit_invalid`. NEVER touches the parent form's submission
/// state (onSubmit handler, submissionAttempts, isSubmitting). The group's
/// own onSubmit validation always re-runs — the field-error short-circuit
/// upstream describes is not observable in its tests, and re-running is
/// what clears previously distributed errors after a fix. `meta` flows
/// through to the submit callback (typed `String` — documented deviation
/// from upstream's arbitrary meta object).
pub fn[V, G] FormGroupApi::handle_submit(
  self : FormGroupApi[V, G],
  on_group_submit? : (G, String?) -> Unit,
  on_group_submit_invalid? : () -> Unit,
  meta? : String,
) -> Unit {
  self.submission_attempts = self.submission_attempts + 1
  let invalid = () => {
    match on_group_submit_invalid {
      Some(f) => f()
      None => ()
    }
  }
  if !self.can_submit() && self.submission_attempts <= 1 {
    invalid()
    return
  }
  // child fields' onSubmit validators (mounted fields under the group only)
  for k in self.form.field_regs.keys() {
    if k.has_prefix(self.lens.key) {
      match self.form.submit_validators.get(k) {
        Some(f) => f(self.form.values)
        None => ()
      }
    }
  }
  // the group's own onSubmit validation re-runs (its distribution replaces
  // / clears previously distributed field slots)
  self.run_validation(Submit)
  if !self.is_valid() {
    invalid()
    return
  }
  match on_group_submit {
    Some(f) => f((self.lens.get)(self.form.values), meta)
    None => ()
  }
}

///|
pub extend GroupFieldError with Debug::{to_repr}

///|
pub extend GroupFieldError with Eq::{not_equal, equal}

///|
pub extend GroupValidationResult with Debug::{to_repr}

///|
pub extend GroupValidationResult with Eq::{not_equal, equal}
