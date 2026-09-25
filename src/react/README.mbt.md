# moonform react — README with doc tests

The `mbt check` blocks below are executed as tests by `moon test` on the
js target (the react package is js-only). They pin the same contracts the
browser demos exercise end-to-end.

## FieldBridge: drive an input

```mbt check
///|
struct RbLogin {
  rb_email : String
} derive(Eq, Debug)

///|
pub extend RbLogin with Eq::{not_equal, equal}

///|
pub extend RbLogin with Debug::{to_repr}

///|
test "doc: FieldBridge refreshes on writes" {
  let form = @core.FormApi::make({ rb_email: "", })
  let bridge = @react.FieldBridge::make(
    form,
    @core.field("email", (v : RbLogin) => v.rb_email, (_v, e) => {
      rb_email: e,
    }),
  )
  bridge.attach()
  bridge.set_value("a@b.c")
  let s = bridge.state()
  inspect(s.value, content="a@b.c")
  inspect(s.is_touched, content="true")
  bridge.detach()
}
```

## GroupBridge: group state drives the step button

```mbt check
///|
struct RbStep {
  rb_title : String
} derive(Eq, Debug)

///|
pub extend RbStep with Eq::{not_equal, equal}

///|
pub extend RbStep with Debug::{to_repr}

///|
struct RbWiz {
  rb_step : RbStep
} derive(Eq, Debug)

///|
pub extend RbWiz with Eq::{not_equal, equal}

///|
pub extend RbWiz with Debug::{to_repr}

///|
test "doc: GroupBridge submit gates on group validity" {
  let form = @core.FormApi::make({ rb_step: { rb_title: "", }, })
  let step = form.group(
    @core.field("step", (v : RbWiz) => v.rb_step, (_v, s) => { rb_step: s, }),
    on_submit_validate=@core.group_validator_value(g => {
      if g.rb_title == "" {
        @core.GroupValidationResult::group_error("Title is required")
      } else {
        @core.GroupValidationResult::valid()
      }
    }),
  )
  let bridge = @react.GroupBridge::make(step)
  bridge.attach()
  let passed : RbCount = { n: 0, }
  bridge.submit(on_group_submit=(_v, _meta) => passed.n = passed.n + 1)
  inspect(passed.n, content="0") // blocked
  inspect(bridge.state().is_group_valid, content="false")
  step.set_value({ rb_title: "ok", })
  bridge.submit(on_group_submit=(_v, _meta) => passed.n = passed.n + 1)
  inspect(passed.n, content="1") // through
  bridge.detach()
}

///|
struct RbCount {
  mut n : Int
}
```

## FormBridge: submit-button state

```mbt check
///|
test "doc: FormBridge reflects the submit lifecycle" {
  let form = @core.FormApi::make({ rb_step: { rb_title: "ok", }, })
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  bridge.submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => done(@core.SubmitResult::ok())),
    ),
  })
  let s = bridge.state()
  inspect(s.is_submitted, content="true")
  inspect(s.can_submit, content="true")
  bridge.detach()
}
```
