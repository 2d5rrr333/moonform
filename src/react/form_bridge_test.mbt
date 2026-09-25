// FormBridge semantics (headless): snapshot identity stability, submit
// lifecycle refresh, form-level error surfacing, attach/detach lifecycle.
// (Full React render cycles run in the browser demos; these tests pin the
// bridge contract the hook relies on.)

///|
struct FbVals {
  fb_name : String
} derive(Eq, Debug)

///|
fn fb_name_l() -> @core.Lens[FbVals, String] {
  @core.field("name", (v : FbVals) => v.fb_name, (_v, n) => { fb_name: n, })
}

///|
test "form bridge: snapshot is identity-stable until a change" {
  let form = @core.FormApi::make({ fb_name: "a", })
  let bridge = @react.FormBridge::make(form)
  let s1 = bridge.state()
  let s2 = bridge.state()
  assert_eq(s1.rev, s2.rev) // same snapshot until refresh
  assert_false(s1.is_submitting)
  assert_false(s1.is_submitted)
  assert_true(s1.can_submit)
  assert_true(s1.submit_error is None)
}

///|
test "form bridge: submit lifecycle refreshes the snapshot" {
  let form = @core.FormApi::make({ fb_name: "a", })
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  bridge.submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => done(@core.SubmitResult::ok())),
    ),
  })
  let s = bridge.state()
  assert_true(s.is_submitted)
  assert_true(s.is_submit_successful)
  assert_false(s.is_submitting)
  assert_eq(s.submission_attempts, 1)
  assert_true(s.rev > 0) // refreshed by the core notification
  bridge.detach()
}

///|
test "form bridge: submit error surfaces in the snapshot" {
  let form = @core.FormApi::make({ fb_name: "a", })
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  bridge.submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => {
        done(@core.SubmitResult::err("boom"))
      }),
    ),
  })
  let s = bridge.state()
  assert_eq(s.submit_error, Some("boom"))
  assert_false(s.is_submit_successful)
  assert_false(s.is_submitted)
  bridge.detach()
}

///|
test "form bridge: field errors flip validity and can_submit" {
  let form = @core.FormApi::make({ fb_name: "", })
  let field = form.field(
    fb_name_l(),
    on_submit_validate=@core.validator(v => {
      if v == "" {
        ["required"]
      } else {
        []
      }
    }),
  )
  field.mount()
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  bridge.submit()
  let s = bridge.state()
  assert_false(s.is_valid_fields)
  assert_false(s.can_submit)
  // fixing the value and resubmitting recovers
  field.set_value("ok")
  bridge.submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => done(@core.SubmitResult::ok())),
    ),
  })
  let s2 = bridge.state()
  assert_true(s2.is_valid_fields)
  assert_true(s2.can_submit)
  bridge.detach()
}

///|
test "form bridge: detach stops refreshes" {
  let form = @core.FormApi::make({ fb_name: "a", })
  let bridge = @react.FormBridge::make(form)
  bridge.attach()
  bridge.submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => done(@core.SubmitResult::ok())),
    ),
  })
  let rev_after_submit = bridge.state().rev
  bridge.detach()
  bridge.submit() // no subscription: snapshot must not refresh
  let s = bridge.state()
  assert_eq(s.rev, rev_after_submit) // stale by contract (detached)
  assert_eq(s.submission_attempts, 1) // the pre-detach attempt only
  // the core moved on; a manual refresh catches up
  bridge.refresh()
  assert_eq(bridge.state().submission_attempts, 2)
}

// real_clock: safe synchronous surface (ids, monotonic now, cancel as a
// no-op). Timer-driven behavior is exercised end-to-end by the browser
// demo's asynchronous submission (headless-verified).

///|
test "real_clock: monotonic ids and now; cancel is a safe no-op" {
  let clock = @react.real_clock()
  let t1 = clock.now()
  assert_true(t1 >= 0)
  // far-future timers, cancelled immediately: nothing fires, ids increase
  let id1 = clock.schedule(60000, () => ())
  let id2 = clock.schedule(60000, () => ())
  assert_true(id2 > id1)
  clock.cancel(id1)
  clock.cancel(id2)
  clock.cancel(id2 + 999) // unknown id: no-op
  assert_true(clock.now() >= t1)
}
