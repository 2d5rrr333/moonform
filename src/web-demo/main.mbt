// Browser login demo: moonform core + rules through the react bridge,
// rendered with tiye/react. The host page (web/index.html) provides
// globalThis.React / ReactDOM (plus the ReactDOMClient alias shim) and
// loads the built bundle as main.js.
//
// Build: moon build src/web-demo --target js --release
//        + copy web-demo.js to web/main.js
// Serve: any static server with web/ as root (see web/README.md)

///|
struct LoginValues {
  email : String
  password : String
} derive(Eq, Debug)

///|
fn email_l() -> @core.Lens[LoginValues, String] {
  @core.field("email", v => v.email, (v, e) => { ..v, email: e, })
}

///|
fn password_l() -> @core.Lens[LoginValues, String] {
  @core.field("password", v => v.password, (v, p) => { ..v, password: p, })
}

///|
struct LoginProps {
  on_logged_in : (String) -> Unit
}

///|
/// Per-component-instance state: created once (use_ref), never rebuilt
/// across re-renders. Form, bridges and handles live here.
struct LoginState {
  form : @core.FormApi[LoginValues]
  email : @formreact.FieldBridge[LoginValues, String]
  password : @formreact.FieldBridge[LoginValues, String]
  email_handle : @formreact.FieldBridgeHook[LoginValues, String]
  password_handle : @formreact.FieldBridgeHook[LoginValues, String]
}

///|
fn build_state() -> LoginState {
  let form = @core.FormApi::make({ email: "", password: "", })
  let email = form.field(
    email_l(),
    on_change_validate=@rules.required()
      .then(@rules.email())
      .then(@rules.min_length(5)),
  )
  let password = form.field(
    password_l(),
    on_change_validate=@rules.required().then(@rules.min_length(8)),
  )
  email.mount()
  password.mount()
  let email_bridge = @formreact.FieldBridge::make(form, email_l())
  let password_bridge = @formreact.FieldBridge::make(form, password_l())
  {
    form,
    email: email_bridge,
    password: password_bridge,
    email_handle: @formreact.use_field_handle(email_bridge),
    password_handle: @formreact.use_field_handle(password_bridge),
  }
}

///|
fn blur_events(
  bridge : @formreact.FieldBridge[LoginValues, String],
) -> @react.ElementEvents {
  let events = @react.ElementEvents::new()
  events.set(@react.Blur, fn(_e) { bridge.blur() })
  events
}

///|
fn for_attr(id : String) -> @react.ElementAttrs {
  let attrs = @react.ElementAttrs::new()
  attrs.set("for", id)
  attrs
}

///|
fn login_component(props : LoginProps) -> @react.VirtualNode {
  // one state per component instance; re-renders reuse it
  let st_ref = @react.use_ref(build_state())
  let st = st_ref.get()
  let (message, set_message) = @react.use_state("")
  let form_events = @react.ElementEvents::new()
  form_events.set(@react.Submit, fn(_e) {
    st.form.handle_submit(submit_options={
      ..@core.SubmitOptions::make(),
      on_submit: Some(
        @core.submit_handler((values, done) => {
          set_message("Welcome, \{values.email}!")
          (props.on_logged_in)(values.email)
          done(@core.SubmitResult::ok())
        }),
      ),
    })
  })
  // subscribe bridges through React's external-store contract so this
  // component re-renders when field state changes
  ignore(
    @react.use_sync_external_store(
      notify => st.email_handle.subscribe(notify),
      () => st.email_handle.get_snapshot(),
    ),
  )
  ignore(
    @react.use_sync_external_store(
      notify => st.password_handle.subscribe(notify),
      () => st.password_handle.get_snapshot(),
    ),
  )
  @react.div(class_name="login-card", [
    @react.h2([@react.VirtualNode::Text("Sign in")]),
    @react.form(event=form_events, [
      @react.label(attrs=for_attr("email"), [@react.VirtualNode::Text("Email")]),
      @react.input(
        id="email",
        type_=@react.InputType::Email,
        placeholder="you@example.com",
        value=st.email_handle.get_snapshot().value,
        on_change=fn(e) { st.email.set_value(e.target_value()) },
        event=blur_events(st.email),
      ),
      @react.div(class_name="err", [
        @react.VirtualNode::Text(
          join_errs(st.email_handle.get_snapshot().errors),
        ),
      ]),
      @react.label(attrs=for_attr("password"), [
        @react.VirtualNode::Text("Password"),
      ]),
      @react.input(
        id="password",
        type_=@react.InputType::Password,
        placeholder="at least 8 characters",
        value=st.password_handle.get_snapshot().value,
        on_change=fn(e) { st.password.set_value(e.target_value()) },
        event=blur_events(st.password),
      ),
      @react.div(class_name="err", [
        @react.VirtualNode::Text(
          join_errs(st.password_handle.get_snapshot().errors),
        ),
      ]),
      @react.button(button_type="submit", [@react.VirtualNode::Text("Sign in")]),
      @react.div(class_name="ok", [@react.VirtualNode::Text(message)]),
    ]),
  ])
}

///|
fn join_errs(errs : Array[String]) -> String {
  if errs.length() > 0 {
    errs.join("; ")
  } else {
    ""
  }
}

///|
extern "js" fn js_render_login(vdom : @dom.JsObscure) -> Unit =
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
  js_render_login(
    @react.component(login_component, { on_logged_in: _ => (), }, []).to_js_obscure(),
  )
}
