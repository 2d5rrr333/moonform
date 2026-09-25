// The React-facing whole-form hook: subscribes the bridge through
// tiye/react's use_sync_external_store and returns the form's current
// snapshot. Mirrors use_field / use_group.

///|
/// The per-component hook state: wraps a bridge bound to the whole form.
pub struct FormBridgeHook[V] {
  bridge : FormBridge[V]
}

///|
/// Build a hook handle for a form (call once per component setup, e.g.
/// with `use_memo_deps` or a ref). The returned handle drives
/// `use_sync_external_store`.
pub fn[V] use_form_handle(bridge : FormBridge[V]) -> FormBridgeHook[V] {
  { bridge, }
}

///|
/// Hook adapter: subscribe wires the bridge's refresh to React's notify
/// (every core change schedules a re-render) and returns an unsubscribe
/// function — React's external-store contract.
pub fn[V] FormBridgeHook::subscribe(
  self : FormBridgeHook[V],
  notify : () -> Unit,
) -> () -> Unit {
  self.bridge.attach_with_notify(notify)
  () => self.bridge.detach()
}

///|
/// Snapshot getter for use_sync_external_store: identity-stable between
/// core notifications (Object.is comparison in React).
pub fn[V] FormBridgeHook::get_snapshot(self : FormBridgeHook[V]) -> FormState {
  self.bridge.state()
}
