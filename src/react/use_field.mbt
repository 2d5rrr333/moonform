// The React-facing hook: subscribes the bridge through tiye/react's
// use_sync_external_store and returns the field's current snapshot.
// React re-renders whenever the snapshot's identity changes — the bridge
// refreshes the snapshot and calls notify on every core notification.

///|
/// Subscribe a field bridge to the component and return its snapshot.
pub fn[V, A : Eq] use_field(bridge : FieldBridge[V, A]) -> FieldState[A] {
  let handle = use_field_handle(bridge)
  // handle.subscribe_fn is identity-stable across renders (the hook struct
  // is created once per component) — React's external-store contract
  @tiye_react.use_sync_external_store(handle.subscribe_fn, () => {
    handle.get_snapshot()
  })
}
