// The React-facing hook: subscribes a form bridge to the component and
// returns the whole-form snapshot. React re-renders whenever the
// snapshot's identity changes — the natural driver for submit-button
// state (disabled/spinner while submitting) and form-level error display.

///|
/// Subscribe a form bridge to the component and return its snapshot.
pub fn[V] use_form(bridge : FormBridge[V]) -> FormState {
  let handle = use_form_handle(bridge)
  let subscribe : (() -> Unit) -> () -> Unit = notify => {
    handle.subscribe(notify)
  }
  let get_snapshot : () -> FormState = () => handle.get_snapshot()
  @tiye_react.use_sync_external_store(subscribe, get_snapshot)
}
