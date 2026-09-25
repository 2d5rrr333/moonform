// GroupBridge: the React-facing bridge for one core FormGroupApi — the
// group counterpart of FieldBridge. The snapshot derives from ALL state
// under the group (the group's own slots plus every child field's meta:
// distributed errors, touched flags, validating), so the bridge subscribes
// with a prefix subscription (`FormApi::subscribe_under`) instead of an
// exact-key one. Snapshot discipline matches FieldBridge: identity-stable
// between core notifications (use_sync_external_store contract).

///|
/// A stable per-group snapshot for React rendering: rebuilt when the core
/// notifies (any change under the group's key), identity-stable between
/// notifications.
pub struct GroupState[G] {
  /// Current group value.
  value : G
  /// Group-level error messages (the group's own slots, lifecycle order;
  /// child field errors live on the fields).
  errors : Array[String]
  is_touched : Bool
  is_fields_valid : Bool
  is_group_valid : Bool
  is_valid : Bool
  is_validating : Bool
  can_submit : Bool
  /// Group-scoped submission counter (never the parent form's).
  submission_attempts : Int
  /// Snapshot revision — increments on every core notification.
  rev : Int
} derive(Debug)

///|
/// Bridge between one core group and React. Create once per component
/// instance, drive it via `use_group` / `use_group_handle`, and wire
/// `submit` into the group's submit button.
pub struct GroupBridge[V, G] {
  group : @core.FormGroupApi[V, G]
  mut snapshot : GroupState[G]
  mut sub_id : Int?
  /// React's re-render callback from use_sync_external_store; set by
  /// `attach_with_notify`, invoked on every core notification.
  mut notify : (() -> Unit)?
}

///|
pub fn[V, G] GroupBridge::make(
  group : @core.FormGroupApi[V, G],
) -> GroupBridge[V, G] {
  {
    group,
    snapshot: build_group_snapshot(group, 0),
    sub_id: None,
    notify: None,
  }
}

///|
fn[V, G] build_group_snapshot(
  group : @core.FormGroupApi[V, G],
  rev : Int,
) -> GroupState[G] {
  {
    value: group.value(),
    errors: group.errors(),
    is_touched: group.is_touched(),
    is_fields_valid: group.is_fields_valid(),
    is_group_valid: group.is_group_valid(),
    is_valid: group.is_valid(),
    is_validating: group.is_validating(),
    can_submit: group.can_submit(),
    submission_attempts: group.submission_attempts(),
    rev,
  }
}

///|
/// Refresh the snapshot from the core (bumps rev) and notify React that
/// the store changed (schedules a re-render). Called on every core
/// notification under the group's key.
pub fn[V, G] GroupBridge::refresh(self : GroupBridge[V, G]) -> Unit {
  let next_rev = self.snapshot.rev + 1
  self.snapshot = build_group_snapshot(self.group, next_rev)
  match self.notify {
    Some(cb) => cb()
    None => ()
  }
}

///|
/// Current snapshot (Object.is-stable until refresh).
pub fn[V, G] GroupBridge::state(self : GroupBridge[V, G]) -> GroupState[G] {
  self.snapshot
}

///|
/// The underlying group handle (submit wiring, validators, listeners).
pub fn[V, G] GroupBridge::group(
  self : GroupBridge[V, G],
) -> @core.FormGroupApi[V, G] {
  self.group
}

///|
/// Subscribe the bridge to every change under the group's key WITHOUT a
/// React notify callback (headless mode; refreshes snapshots only). For
/// React wiring prefer `attach_with_notify`.
pub fn[V, G] GroupBridge::attach(self : GroupBridge[V, G]) -> Unit {
  match self.sub_id {
    Some(_) => () // already attached
    None =>
      self.sub_id = Some(
        self.group.form.subscribe_under(
          self.group.key(),
          kinds=@core.ChangeKind::value_and_meta(),
          () => self.refresh(),
        ),
      )
  }
}

///|
/// Subscribe with React's notify callback (use_sync_external_store
/// contract): every core change under the group refreshes the snapshot AND
/// schedules a React re-render.
pub fn[V, G] GroupBridge::attach_with_notify(
  self : GroupBridge[V, G],
  notify : () -> Unit,
) -> Unit {
  self.notify = Some(notify)
  self.attach()
}

///|
/// Unsubscribe (component unmount).
pub fn[V, G] GroupBridge::detach(self : GroupBridge[V, G]) -> Unit {
  match self.sub_id {
    Some(id) => {
      self.group.form.unsubscribe(id)
      self.sub_id = None
      self.notify = None
    }
    None => ()
  }
}

///|
/// Trigger the group's submission (submit-button wiring): validates the
/// child fields and the group's own onSubmit validator, reports through
/// the callbacks, never touches the parent form's submit state.
pub fn[V, G] GroupBridge::submit(
  self : GroupBridge[V, G],
  on_group_submit? : (G, String?) -> Unit,
  on_group_submit_invalid? : () -> Unit,
  meta? : String,
) -> Unit {
  // None callbacks are no-ops in the core; synthesize them so the
  // optional parameters forward without combinatorial branching.
  let f = on_group_submit.unwrap_or((_v, _meta) => ())
  let g = on_group_submit_invalid.unwrap_or(() => ())
  match meta {
    Some(m) =>
      self.group.handle_submit(
        on_group_submit=f,
        on_group_submit_invalid=g,
        meta=m,
      )
    None =>
      self.group.handle_submit(on_group_submit=f, on_group_submit_invalid=g)
  }
}

///|
pub extend GroupState with Debug::{to_repr}
