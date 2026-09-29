// moonform/react: tiye/react adapter over the core (headless) form.
//
// The bridge follows React's `use_sync_external_store` contract:
// - subscribe(notify): attaches the bridge to the core and calls `notify`
//   on every relevant core change so React schedules a re-render
// - get_snapshot: MUST return an Object.is-stable snapshot value between
//   changes — FieldState snapshots are rebuilt on every core change, and
//   the adapter caches the last snapshot per field so React sees identity
//   stability while the field is unchanged.
//
// tiye/react targets the JS backend only.

///|
/// A stable per-field snapshot for React rendering: rebuilt when the core
/// notifies, identity-stable between notifications.
pub struct FieldState[A] {
  /// Current field value. After a structural array change removed the
  /// field's slot, this keeps the last live value (the lens address is
  /// stale — the structural-change contract has adapters re-mount per
  /// slot; `array_version` on the ARRAY field's snapshot is the signal).
  value : A
  /// Flattened error messages (lifecycle order).
  errors : Array[String]
  is_touched : Bool
  is_blurred : Bool
  /// Derived dirty: the current value differs from the form default
  /// (upstream `isDirty` semantics — NOT the sticky stored flag). A stale
  /// slot vs a live slot is dirty (the field moved).
  is_dirty : Bool
  is_validating : Bool
  is_valid : Bool
  array_version : Int
  /// Snapshot revision — increments on every core notification.
  rev : Int
} derive(Debug)

///|
/// Bridge between one core field and React. Create once per component
/// instance (e.g. stored in a ref), drive it via `use_field` /
/// `use_field_handle`, and wire `set_value` / `blur` into input handlers.
pub struct FieldBridge[V, A] {
  form : @core.FormApi[V]
  lens : @core.Lens[V, A]
  mut snapshot : FieldState[A]
  mut sub_id : Int?
  /// React's re-render callback from use_sync_external_store; set by
  /// `attach_with_notify`, invoked on every core notification.
  mut notify : (() -> Unit)?
}

///|
pub fn[V, A : Eq] FieldBridge::make(
  form : @core.FormApi[V],
  lens : @core.Lens[V, A],
) -> FieldBridge[V, A] {
  {
    form,
    lens,
    snapshot: build_snapshot(form, lens, 0, lens.try_get(form.values())),
    sub_id: None,
    notify: None,
  }
}

///|
fn[V, A : Eq] build_snapshot(
  form : @core.FormApi[V],
  lens : @core.Lens[V, A],
  rev : Int,
  stale_fallback : A?,
) -> FieldState[A] {
  let meta = form.field_meta(lens.key)
  // stale array slot: keep the last live value (never abort on the
  // out-of-range index — the core's try_get contract)
  let value = match lens.try_get(form.values()) {
    Some(v) => v
    None =>
      match stale_fallback {
        Some(v) => v
        None => form.get_value(lens) // never stale at construction
      }
  }
  let cur_opt = lens.try_get(form.values())
  let def_opt = lens.try_get(form.default_values())
  let is_dirty = match (cur_opt, def_opt) {
    (Some(cur), Some(def)) => cur != def
    (None, None) => false
    // a stale slot vs a live slot (or vice versa): the field moved — dirty
    _ => true
  }
  {
    value,
    errors: meta.errors(),
    is_touched: meta.is_touched,
    is_blurred: meta.is_blurred,
    is_dirty,
    is_validating: meta.is_validating,
    is_valid: meta.is_valid(),
    array_version: meta.array_version,
    rev,
  }
}

///|
/// Rebuild the snapshot from the core WITHOUT notifying React — used on
/// attach so a re-attached bridge reads fresh state (the core may have
/// changed while detached).
fn[V, A : Eq] FieldBridge::rebuild(self : FieldBridge[V, A]) -> Unit {
  let stale_fallback : A? = Some(self.snapshot.value)
  self.snapshot = build_snapshot(
    self.form,
    self.lens,
    self.snapshot.rev + 1,
    stale_fallback,
  )
}

///|
/// Refresh the snapshot from the core (bumps rev) and notify React that
/// the store changed (schedules a re-render). Called on every core
/// notification for this field.
pub fn[V, A : Eq] FieldBridge::refresh(self : FieldBridge[V, A]) -> Unit {
  self.rebuild()
  match self.notify {
    Some(cb) => cb()
    None => ()
  }
}

///|
/// Current snapshot (Object.is-stable until refresh).
pub fn[V, A] FieldBridge::state(self : FieldBridge[V, A]) -> FieldState[A] {
  self.snapshot
}

///|
/// Subscribe the bridge to its field's changes WITHOUT a React notify
/// callback (headless mode; refreshes snapshots only). For React wiring
/// prefer `attach_with_notify`. Re-attaching rebuilds the snapshot — the
/// core may have changed while detached.
pub fn[V, A : Eq] FieldBridge::attach(self : FieldBridge[V, A]) -> Unit {
  match self.sub_id {
    Some(_) => () // already attached
    None => {
      self.sub_id = Some(
        self.form.subscribe_field(
          self.lens.key,
          kinds=@core.ChangeKind::value_and_meta(),
          () => self.refresh(),
        ),
      )
      self.rebuild()
    }
  }
}

///|
/// Subscribe with React's notify callback (use_sync_external_store
/// contract): every core change refreshes the snapshot AND schedules a
/// React re-render.
pub fn[V, A : Eq] FieldBridge::attach_with_notify(
  self : FieldBridge[V, A],
  notify : () -> Unit,
) -> Unit {
  self.notify = Some(notify)
  self.attach()
}

///|
/// Unsubscribe (component unmount).
pub fn[V, A] FieldBridge::detach(self : FieldBridge[V, A]) -> Unit {
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
/// Write a new field value through the bridge (onChange handler wiring).
pub fn[V, A] FieldBridge::set_value(
  self : FieldBridge[V, A],
  value : A,
) -> Unit {
  self.form.set_value(self.lens, value)
}

///|
/// Mark the field blurred (onBlur handler wiring).
pub fn[V, A] FieldBridge::blur(self : FieldBridge[V, A]) -> Unit {
  self.form.blur_field(self.lens.key)
}

///|
pub extend FieldState with Debug::{to_repr}
