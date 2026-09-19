// The React-facing hook: subscribes the bridge through tiye/react's
// use_sync_external_store and returns the field's current snapshot.
// React re-renders whenever the snapshot's identity changes — the bridge
// refreshes the snapshot and calls notify on every core notification.

///|
/// Subscribe a field bridge to the component and return its snapshot.
pub fn[V, A] use_field(bridge : FieldBridge[V, A]) -> FieldState[A] {
  let handle = use_field_handle(bridge)
  let subscribe : (() -> Unit) -> () -> Unit = notify => {
    handle.subscribe(notify)
  }
  let get_snapshot : () -> FieldState[A] = () => handle.get_snapshot()
  @tiye_react.use_sync_external_store(subscribe, get_snapshot)
}
