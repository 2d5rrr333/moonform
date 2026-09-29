// The React-facing hook: subscribes a form bridge to the component and
// returns the whole-form snapshot. React re-renders whenever the
// snapshot's identity changes — the natural driver for submit-button
// state (disabled/spinner while submitting) and form-level error display.

///|
/// Subscribe a form bridge to the component and return its snapshot.
pub fn[V] use_form(bridge : FormBridge[V]) -> FormState {
  let handle = use_form_handle(bridge)
  // handle.subscribe_fn is identity-stable across renders (the hook struct
  // is created once per component) — React's external-store contract
  @tiye_react.use_sync_external_store(handle.subscribe_fn, () => {
    handle.get_snapshot()
  })
}
