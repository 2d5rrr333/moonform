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
  /// Current field value.
  value : A
  /// Flattened error messages (lifecycle order).
  errors : Array[String]
  is_touched : Bool
  is_blurred : Bool
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
pub fn[V, A] FieldBridge::make(
  form : @core.FormApi[V],
  lens : @core.Lens[V, A],
) -> FieldBridge[V, A] {
  {
    form,
    lens,
    snapshot: build_snapshot(form, lens, 0),
    sub_id: None,
    notify: None,
  }
}

///|
fn[V, A] build_snapshot(
  form : @core.FormApi[V],
  lens : @core.Lens[V, A],
  rev : Int,
) -> FieldState[A] {
  let meta = form.field_meta(lens.key)
  {
    value: form.get_value(lens),
    errors: meta.errors(),
    is_touched: meta.is_touched,
    is_blurred: meta.is_blurred,
    is_dirty: meta.is_dirty,
    is_validating: meta.is_validating,
    is_valid: meta.is_valid(),
    array_version: meta.array_version,
    rev,
  }
}

///|
/// Refresh the snapshot from the core (bumps rev) and notify React that
/// the store changed (schedules a re-render). Called on every core
/// notification for this field.
pub fn[V, A] FieldBridge::refresh(self : FieldBridge[V, A]) -> Unit {
  let next_rev = self.snapshot.rev + 1
  self.snapshot = build_snapshot(self.form, self.lens, next_rev)
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
/// prefer `attach_with_notify`.
pub fn[V, A] FieldBridge::attach(self : FieldBridge[V, A]) -> Unit {
  match self.sub_id {
    Some(_) => () // already attached
    None =>
      self.sub_id = Some(
        self.form.subscribe_field(
          self.lens.key,
          kinds=@core.ChangeKind::value_and_meta(),
          () => self.refresh(),
        ),
      )
  }
}

///|
/// Subscribe with React's notify callback (use_sync_external_store
/// contract): every core change refreshes the snapshot AND schedules a
/// React re-render.
pub fn[V, A] FieldBridge::attach_with_notify(
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
