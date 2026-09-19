// React-hook integration: `use_field` wires a FieldBridge into React's
// external-store subscription (tiye/react's use_sync_external_store).
//
// Snapshot discipline (tiye/react README contract): the subscribe function
// is stable across renders; the snapshot value keeps the same identity
// while the store has not changed. FieldBridge guarantees this by caching
// FieldState and rebuilding it only on core notifications.

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
/// Hook adapter: subscribe returns an unsubscribe function (React
/// external-store contract).
pub fn[V, A] FieldBridgeHook::subscribe(
  self : FieldBridgeHook[V, A],
) -> () -> Unit {
  self.bridge.attach()
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
