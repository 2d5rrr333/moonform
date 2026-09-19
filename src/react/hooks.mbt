// React-hook integration: `use_field` wires a FieldBridge into React's
// external-store subscription (tiye/react's use_sync_external_store).
//
// Snapshot discipline (React contract): the subscribe function is stable
// across renders; the snapshot value keeps the same identity while the
// store has not changed. FieldBridge guarantees this by caching FieldState
// and rebuilding it only on core notifications — and by notifying React
// (scheduling a re-render) on every refresh.

///|
/// The per-component hook state: wraps a bridge bound to one field.
pub struct FieldBridgeHook[V, A] {
  bridge : FieldBridge[V, A]
}

///|
/// Build a hook handle for a field (call once per component setup, e.g.
/// with `use_memo_deps` or a ref). The returned handle drives
/// `use_sync_external_store`.
pub fn[V, A] use_field_handle(
  bridge : FieldBridge[V, A],
) -> FieldBridgeHook[V, A] {
  { bridge, }
}

///|
/// Hook adapter: subscribe wires the bridge's refresh to React's notify
/// (every core change schedules a re-render) and returns an unsubscribe
/// function — React's external-store contract.
pub fn[V, A] FieldBridgeHook::subscribe(
  self : FieldBridgeHook[V, A],
  notify : () -> Unit,
) -> () -> Unit {
  self.bridge.attach_with_notify(notify)
  () => self.bridge.detach()
}

///|
/// Snapshot getter for use_sync_external_store: identity-stable between
/// core notifications (Object.is comparison in React).
pub fn[V, A] FieldBridgeHook::get_snapshot(
  self : FieldBridgeHook[V, A],
) -> FieldState[A] {
  self.bridge.state()
}
