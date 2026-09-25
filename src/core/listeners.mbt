// Form-level change listeners (upstream FormApi `listeners.onChange` /
// `listeners.onChangeGroup` with `onChangeDebounceMs` /
// `onChangeGroupDebounceMs`): debounced on the form's injected Clock —
// virtual in tests, real timers in host adapters. The two listeners debounce
// independently, mirroring upstream.

///|
/// A form-level change listener with an optional debounce window. Debounced
/// listeners fire on the trailing edge; re-triggers inside the window
/// reschedule. A zero window (or a form without a Clock) fires synchronously.
pub struct ChangeListener {
  cb : (Key) -> Unit
  debounce_ms : Int
  mut timer : Int?
}

///|
fn ChangeListener::make(
  cb : (Key) -> Unit,
  debounce_ms : Int,
) -> ChangeListener {
  { cb, debounce_ms, timer: None, }
}

///|
fn ChangeListener::fire(
  self : ChangeListener,
  clock : Clock?,
  key : Key,
) -> Unit {
  if self.debounce_ms <= 0 {
    (self.cb)(key)
    return
  }
  let clock = match clock {
    Some(c) => c
    None => {
      (self.cb)(key) // no time source: degrade to synchronous firing
      return
    }
  }
  match self.timer {
    Some(id) => clock.cancel(id)
    None => ()
  }
  self.timer = Some(
    clock.schedule(self.debounce_ms, () => {
      self.timer = None
      (self.cb)(key)
    }),
  )
}

///|
/// Fire the form-level onChange listener for a field change at `key`.
fn[V] FormApi::fire_on_change(self : FormApi[V], key : Key) -> Unit {
  match self.on_change_listener {
    Some(l) => l.fire(self.clock, key)
    None => ()
  }
}

///|
/// Fire the form-level onChangeGroup listener for a change inside the group
/// at `group_key` (receives the group's key, mirroring upstream's
/// `{formApi, groupApi}` payload).
fn[V] FormApi::fire_on_change_group(self : FormApi[V], group_key : Key) -> Unit {
  match self.on_change_group_listener {
    Some(l) => l.fire(self.clock, group_key)
    None => ()
  }
}

///|
/// Dispatch a field change to mounted groups: every group whose key prefixes
/// `changed` runs its change validation (with error distribution) and its
/// onChange listener against the current values. Returns the matching group
/// keys (canonical order).
fn[V] FormApi::dispatch_groups(self : FormApi[V], changed : Key) -> Array[Key] {
  let hits : Array[Key] = []
  for k in self.group_regs.keys() {
    if changed.has_prefix(k) {
      match self.group_regs.get(k) {
        Some(reg) => {
          (reg.dispatch_change)(self.values)
          hits.push(k)
        }
        None => ()
      }
    }
  }
  hits.sort()
  hits
}
