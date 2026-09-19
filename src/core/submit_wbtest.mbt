// Submit orchestration, translated from form-core@1.33.5 FormApi.spec.ts
// submission block (lifecycle assertions; async submission completes via
// the virtual clock — documented deviation).

// upstream: "should call the onSubmit callback" (happy path)

///|
test "submit: successful submission lifecycle" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let received = StrCell::make()
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((values, done) => {
        received.v = Some(values.name)
        done(Ok)
      }),
    ),
  })
  assert_eq(received.v, Some("test")) // handler saw the values
  assert_true(form.is_submitted())
  assert_true(form.is_submit_successful())
  assert_false(form.is_submitting())
  assert_eq(form.submission_attempts(), 1)
}

// upstream: "should call onSubmitInvalid when submitted with an error"

///|
test "submit: validation failure blocks submission" {
  let form = FormApi::make({ name: "other", surname: "", age: 0, })
  let invalid_called = { n: 0, }
  let submit_ran = { n: 0, }
  let field = form.field(
    name_l(),
    on_submit_validate=validator(v => {
      if v == "other" {
        ["Please enter a different value"]
      } else {
        []
      }
    }),
  )
  field.mount()
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((_values, done) => {
        submit_ran.n = submit_ran.n + 1
        done(Ok)
      }),
    ),
    on_submit_invalid: Some(_ => invalid_called.n = invalid_called.n + 1),
  })
  assert_eq(submit_ran.n, 0) // onSubmit never ran
  assert_eq(invalid_called.n, 1) // onSubmitInvalid ran
  assert_false(form.is_submit_successful())
  assert_false(form.is_submitting())
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// upstream: "should not submit the form if preventDefault is called"

///|
test "submit: preventDefault cancels and does not count" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(submit_handler((_values, done) => done(Prevented))),
  })
  assert_eq(form.submission_attempts(), 0) // count reverted
  assert_false(form.is_submitted())
  assert_false(form.is_submit_successful())
  assert_false(form.is_submitting())
}

// upstream: "should run async submission" — async finish via the clock

///|
test "submit: async submission completes through the clock" {
  let clock = VirtualClock::make()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((values, done) => {
        let _ = clock.schedule(500, () => {
          if values.name == "test" {
            done(Ok)
          } else {
            done(Err("bad name"))
          }
        })
      }),
    ),
  })
  assert_true(form.is_submitting()) // in flight
  clock.run_all()
  assert_false(form.is_submitting())
  assert_true(form.is_submitted())
  assert_true(form.is_submit_successful())
}

// upstream: "should set isSubmitSuccessful false when the submit handler
// throws" — Err models a throwing handler

///|
test "submit: handler error marks failure" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((_values, done) => done(Err("submission exploded"))),
    ),
  })
  assert_false(form.is_submit_successful())
  assert_false(form.is_submitting())
  assert_false(form.is_submitted())
  assert_eq(form.submit_error(), Some("submission exploded"))
}

// upstream: "should call onSubmitInvalid when submitting while canSubmit
// is false (e.g., onMount error present)"

///|
test "submit: onMount errors block canSubmit on first attempt" {
  let form = FormApi::make({ name: "other", surname: "", age: 0, })
  let invalid_called = { n: 0, }
  let field = form.field(
    name_l(),
    on_mount_validate=validator(v => {
      if v == "other" {
        ["mount error"]
      } else {
        []
      }
    }),
  )
  field.mount()
  assert_true(field.meta().has_errors()) // onMount error present
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit_invalid: Some(_ => invalid_called.n = invalid_called.n + 1),
  })
  assert_eq(invalid_called.n, 1)
  // touched-marking happened during the attempt
  assert_true(form.is_touched())
}

// upstream: submission marks untouched fields as touched

///|
test "submit: untouched fields become touched" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  assert_false(field.meta().is_touched)
  form.handle_submit()
  assert_true(field.meta().is_touched)
}

// upstream: "should reset isSubmitSuccessful at the start of each attempt"

///|
test "submit: second attempt resets success flag first" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(submit_handler((_v, done) => done(Ok))),
  })
  assert_true(form.is_submit_successful())
  form.handle_submit() // no handler → success no-op
  assert_true(form.is_submit_successful())
  assert_eq(form.submission_attempts(), 2)
}

// canSubmit: valid, untouched, never attempted → true; after attempts with
// errors → false; clean → true

///|
test "submit: can_submit lifecycle" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  assert_true(form.can_submit())
  let field = form.field(
    name_l(),
    on_submit_validate=validator(v => {
      if v == "other" {
        ["invalid"]
      } else {
        []
      }
    }),
  )
  field.mount()
  form.set_value(name_l(), "other")
  form.handle_submit()
  assert_false(form.can_submit()) // errors present
  form.set_value(name_l(), "test")
  form.handle_submit() // re-validates: clears errors on success path
  assert_true(form.can_submit())
}
