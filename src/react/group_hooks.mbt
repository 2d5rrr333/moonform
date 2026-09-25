// The React-facing group hook: subscribes the bridge through tiye/react's
// use_sync_external_store and returns the group's current snapshot.
// Mirrors use_field; the bridge's prefix subscription covers every change
// under the group's key (child fields included).

///|
/// The per-component hook state: wraps a bridge bound to one group.
pub struct GroupBridgeHook[V, G] {
  bridge : GroupBridge[V, G]
}

///|
/// Build a hook handle for a group (call once per component setup, e.g.
/// with `use_memo_deps` or a ref). The returned handle drives
/// `use_sync_external_store`.
pub fn[V, G] use_group_handle(
  bridge : GroupBridge[V, G],
) -> GroupBridgeHook[V, G] {
  { bridge, }
}

///|
/// Hook adapter: subscribe wires the bridge's refresh to React's notify
/// (every core change under the group schedules a re-render) and returns
/// an unsubscribe function — React's external-store contract.
pub fn[V, G] GroupBridgeHook::subscribe(
  self : GroupBridgeHook[V, G],
  notify : () -> Unit,
) -> () -> Unit {
  self.bridge.attach_with_notify(notify)
  () => self.bridge.detach()
}

///|
/// Snapshot getter for use_sync_external_store: identity-stable between
/// core notifications (Object.is comparison in React).
pub fn[V, G] GroupBridgeHook::get_snapshot(
  self : GroupBridgeHook[V, G],
) -> GroupState[G] {
  self.bridge.state()
}
