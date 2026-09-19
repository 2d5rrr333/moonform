// The React-facing hook: subscribes the bridge through tiye/react's
// use_sync_external_store and returns the field's current snapshot.

///|
/// Subscribe a field bridge to the component and return its snapshot.
/// React re-renders whenever the snapshot's identity changes (i.e. on
/// every core notification for this field — see FieldBridge for the
/// stability contract).
pub fn[V, A] use_field(bridge : FieldBridge[V, A]) -> FieldState[A] {
  let handle = use_field_handle(bridge)
  let subscribe : (() -> Unit) -> () -> Unit = _notify => handle.subscribe()
  let get_snapshot : () -> FieldState[A] = () => handle.get_snapshot()
  @tiye_react.use_sync_external_store(subscribe, get_snapshot)
}
