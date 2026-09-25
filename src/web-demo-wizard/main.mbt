// Browser wizard demo: multi-step form with FormGroupApi — step 1 uses a
// moonschema schema as the group validator (errors distribute to the child
// fields via JSON-Pointer paths), step 2 uses a manual dual-channel
// validator (group-level error + field error). Group submission gates each
// step; the final step submits the whole form.
//
// Build: moon build src/web-demo-wizard --target js --release
//        + copy web-demo-wizard.js to web/wizard.js
// Serve: any static server with web/ as root (see web/README.md)

///|
struct WizAccount {
  username : String
  email : String
} derive(Eq, ToJson, Debug)

///|
struct WizProfile {
  nickname : String
} derive(Eq, ToJson, Debug)

///|
struct WizValues {
  account : WizAccount
  profile : WizProfile
} derive(Eq, ToJson, Debug)

///|
fn wiz_account_l() -> @core.Lens[WizValues, WizAccount] {
  @core.field("account", (v : WizValues) => v.account, (v, a) => {
    ..v,
    account: a,
  })
}

///|
fn wiz_profile_l() -> @core.Lens[WizValues, WizProfile] {
  @core.field("profile", (v : WizValues) => v.profile, (v, p) => {
    ..v,
    profile: p,
  })
}

///|
fn wiz_username_l() -> @core.Lens[WizValues, String] {
  wiz_account_l().compose(
    @core.field("username", (a : WizAccount) => a.username, (a, u) => {
      ..a,
      username: u,
    }),
  )
}

///|
fn wiz_email_l() -> @core.Lens[WizValues, String] {
  wiz_account_l().compose(
    @core.field("email", (a : WizAccount) => a.email, (a, e) => {
      ..a,
      email: e,
    }),
  )
}

///|
fn wiz_nickname_l() -> @core.Lens[WizValues, String] {
  wiz_profile_l().compose(
    @core.field("nickname", (p : WizProfile) => p.nickname, (_p, n) => {
      nickname: n,
    }),
  )
}

///|
/// Step 1 validator: a compiled moonschema schema over the ACCOUNT value —
/// errors distribute to the child fields by JSON-Pointer path.
fn wiz_account_schema() -> @moonschema.Schema {
  @builder.object({
    "username": @builder.string().min_len(3),
    "email": @builder.string().email(),
  }).compile() catch {
    _ => abort("schema compile failed")
  }
}

///|
/// Step 2 validator: manual dual-channel judgment — an empty nickname is a
/// group-level error; a too-short nickname is a field error.
fn wiz_profile_validator() -> @core.GroupValidator[WizProfile, WizValues] {
  @core.group_validator_value(p => {
    if p.nickname == "" {
      @core.GroupValidationResult::group_error("Nickname is required")
    } else if p.nickname.length() < 3 {
      @core.GroupValidationResult::fields([
        (@core.Key::field("nickname"), "Nickname needs 3+ characters"),
      ])
    } else {
      @core.GroupValidationResult::valid()
    }
  })
}

///|
struct WizFinish {
  on_done : (String) -> Unit
}

///|
/// Per-component-instance state: created once (use_ref), never rebuilt
/// across re-renders. Form, groups, bridges and handles live here.
struct WizardState {
  form : @core.FormApi[WizValues]
  step1_bridge : @formreact.GroupBridge[WizValues, WizAccount]
  step2_bridge : @formreact.GroupBridge[WizValues, WizProfile]
  username : @formreact.FieldBridge[WizValues, String]
  email : @formreact.FieldBridge[WizValues, String]
  nickname : @formreact.FieldBridge[WizValues, String]
  username_handle : @formreact.FieldBridgeHook[WizValues, String]
  email_handle : @formreact.FieldBridgeHook[WizValues, String]
  nickname_handle : @formreact.FieldBridgeHook[WizValues, String]
  step1_handle : @formreact.GroupBridgeHook[WizValues, WizAccount]
  step2_handle : @formreact.GroupBridgeHook[WizValues, WizProfile]
}

///|
fn wiz_build_state() -> WizardState {
  let schema_v : @core.GroupValidator[WizAccount, WizValues] = @formSchema.schema_group_validator(
    wiz_account_schema(),
  )
  let form = @core.FormApi::make({
    account: { username: "", email: "", },
    profile: { nickname: "", },
  })
  let step1 = form.group(
    wiz_account_l(),
    on_change_validate=schema_v,
    on_submit_validate=schema_v,
  )
  let step2 = form.group(
    wiz_profile_l(),
    on_change_validate=wiz_profile_validator(),
    on_submit_validate=wiz_profile_validator(),
  )
  let username = form.field(wiz_username_l())
  let email = form.field(wiz_email_l())
  let nickname = form.field(wiz_nickname_l())
  step1.mount()
  step2.mount()
  username.mount()
  email.mount()
  nickname.mount()
  let step1_bridge = @formreact.GroupBridge::make(step1)
  let step2_bridge = @formreact.GroupBridge::make(step2)
  let username_bridge = @formreact.FieldBridge::make(form, wiz_username_l())
  let email_bridge = @formreact.FieldBridge::make(form, wiz_email_l())
  let nickname_bridge = @formreact.FieldBridge::make(form, wiz_nickname_l())
  {
    form,
    step1_bridge,
    step2_bridge,
    username: username_bridge,
    email: email_bridge,
    nickname: nickname_bridge,
    username_handle: @formreact.use_field_handle(username_bridge),
    email_handle: @formreact.use_field_handle(email_bridge),
    nickname_handle: @formreact.use_field_handle(nickname_bridge),
    step1_handle: @formreact.use_group_handle(step1_bridge),
    step2_handle: @formreact.use_group_handle(step2_bridge),
  }
}

///|
fn wiz_blur_events(
  bridge : @formreact.FieldBridge[WizValues, String],
) -> @react.ElementEvents {
  let events = @react.ElementEvents::new()
  events.set(@react.Blur, fn(_e) { bridge.blur() })
  events
}

///|
fn wiz_for_attr(id : String) -> @react.ElementAttrs {
  let attrs = @react.ElementAttrs::new()
  attrs.set("for", id)
  attrs
}

///|
fn wiz_field(
  id : String,
  label : String,
  handle : @formreact.FieldBridgeHook[WizValues, String],
  bridge : @formreact.FieldBridge[WizValues, String],
  placeholder : String,
) -> @react.VirtualNode {
  let snap = handle.get_snapshot()
  @react.div([
    @react.label(attrs=wiz_for_attr(id), [@react.VirtualNode::Text(label)]),
    @react.input(
      id~,
      placeholder~,
      value=snap.value,
      on_change=fn(e) { bridge.set_value(e.target_value()) },
      event=wiz_blur_events(bridge),
    ),
    @react.div(class_name="err", [
      @react.VirtualNode::Text(wiz_join_errs(snap.errors)),
    ]),
  ])
}

///|
fn wiz_join_errs(errs : Array[String]) -> String {
  if errs.length() > 0 {
    errs.join("; ")
  } else {
    ""
  }
}

///|
fn wizard_component(props : WizFinish) -> @react.VirtualNode {
  // one state per component instance; re-renders reuse it
  let st_ref = @react.use_ref(wiz_build_state())
  let st = st_ref.get()
  let (step, set_step) = @react.use_state(1)
  let (message, set_message) = @react.use_state("")
  // subscribe bridges through React's external-store contract so this
  // component re-renders when field or group state changes
  ignore(
    @react.use_sync_external_store(
      notify => st.username_handle.subscribe(notify),
      () => st.username_handle.get_snapshot(),
    ),
  )
  ignore(
    @react.use_sync_external_store(
      notify => st.email_handle.subscribe(notify),
      () => st.email_handle.get_snapshot(),
    ),
  )
  ignore(
    @react.use_sync_external_store(
      notify => st.nickname_handle.subscribe(notify),
      () => st.nickname_handle.get_snapshot(),
    ),
  )
  ignore(
    @react.use_sync_external_store(
      notify => st.step1_handle.subscribe(notify),
      () => st.step1_handle.get_snapshot(),
    ),
  )
  ignore(
    @react.use_sync_external_store(
      notify => st.step2_handle.subscribe(notify),
      () => st.step2_handle.get_snapshot(),
    ),
  )
  if step == 1 {
    let group_errs = st.step1_handle.get_snapshot().errors
    @react.div(class_name="login-card", [
      @react.h2([@react.VirtualNode::Text("Create your account")]),
      wiz_field(
        "username",
        "Username",
        st.username_handle,
        st.username,
        "3+ characters",
      ),
      wiz_field("email", "Email", st.email_handle, st.email, "you@example.com"),
      @react.div(class_name="err", [
        @react.VirtualNode::Text(wiz_join_errs(group_errs)),
      ]),
      @react.button(
        button_type="button",
        on_click=fn(_e) {
          // group submission gates the step; the form's submit state is
          // never touched by it
          st.step1_bridge.submit(on_group_submit=(_v, _meta) => set_step(2))
        },
        [@react.VirtualNode::Text("Next")],
      ),
    ])
  } else {
    let group_errs = st.step2_handle.get_snapshot().errors
    @react.div(class_name="login-card", [
      @react.h2([@react.VirtualNode::Text("Your profile")]),
      wiz_field(
        "nickname",
        "Nickname",
        st.nickname_handle,
        st.nickname,
        "3+ characters",
      ),
      @react.div(class_name="err", [
        @react.VirtualNode::Text(wiz_join_errs(group_errs)),
      ]),
      @react.div(class_name="row", [
        @react.button(button_type="button", on_click=fn(_e) { set_step(1) }, [
          @react.VirtualNode::Text("Back"),
        ]),
        @react.button(
          button_type="button",
          on_click=fn(_e) {
            st.step2_bridge.submit(on_group_submit=(_v, _meta) => {
              // both steps passed: submit the whole form
              st.form.handle_submit(submit_options={
                ..@core.SubmitOptions::make(),
                on_submit: Some(
                  @core.submit_handler((values, done) => {
                    set_message("Done, \{values.profile.nickname}!")
                    (props.on_done)(values.profile.nickname)
                    done(@core.SubmitResult::ok())
                  }),
                ),
              })
            })
          },
          [@react.VirtualNode::Text("Finish")],
        ),
      ]),
      @react.div(class_name="ok", [@react.VirtualNode::Text(message)]),
    ])
  }
}

///|
extern "js" fn js_render_wizard(vdom : @dom.JsObscure) -> Unit =
  #| (vdom) => {
  #|   const app = globalThis.document.getElementById("app");
  #|   if (app === null) return;
  #|   const roots = (globalThis.__mfRoots ??= new WeakMap());
  #|   let root = roots.get(app);
  #|   if (!root) {
  #|     root = (globalThis.ReactDOMClient ?? globalThis.ReactDOM).createRoot(app);
  #|     roots.set(app, root);
  #|   }
  #|   root.render(vdom);
  #| }

///|
fn main {
  js_render_wizard(
    @react.component(wizard_component, { on_done: _ => (), }, []).to_js_obscure(),
  )
}

///|
pub extend WizAccount with Eq::{not_equal, equal}

///|
pub extend WizAccount with ToJson::{to_json}

///|
pub extend WizAccount with Debug::{to_repr}

///|
pub extend WizProfile with Eq::{not_equal, equal}

///|
pub extend WizProfile with ToJson::{to_json}

///|
pub extend WizProfile with Debug::{to_repr}

///|
pub extend WizValues with Eq::{not_equal, equal}

///|
pub extend WizValues with ToJson::{to_json}

///|
pub extend WizValues with Debug::{to_repr}
