// The React-facing hook: subscribes a group bridge to the component and
// returns the group's current snapshot. React re-renders whenever the
// snapshot's identity changes — the bridge refreshes the snapshot and
// calls notify on every core notification under the group's key.

///|
/// Subscribe a group bridge to the component and return its snapshot.
pub fn[V, G] use_group(bridge : GroupBridge[V, G]) -> GroupState[G] {
  let handle = use_group_handle(bridge)
  let subscribe : (() -> Unit) -> () -> Unit = notify => {
    handle.subscribe(notify)
  }
  let get_snapshot : () -> GroupState[G] = () => handle.get_snapshot()
  @tiye_react.use_sync_external_store(subscribe, get_snapshot)
}
