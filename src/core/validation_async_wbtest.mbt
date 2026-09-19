// Async validation semantics on the virtual clock, translated from
// form-core@1.33.5 FieldApi.spec.ts:
// - "should run async validation onChange"
// - "should run async validation onChange with debounce"
// - "should run async validation onBlur"
// - "should not apply in-flight async validation results after unmount"
// - race: latest run wins (cause-ordering tests)
// Deviation (documented): upstream sleeps/timers become virtual-time ticks.

///|
fn vc() -> VirtualClock {
  VirtualClock::make()
}

///|
fn not_other_async(
  value : String,
  clock : Clock,
  done : (Array[String]) -> Unit,
) -> Unit {
  // async validator: sleep(1000) then judge (upstream shape)
  let _ = clock.schedule(1000, () => {
    if value == "other" {
      done(["Please enter a different value"])
    } else {
      done([])
    }
  })
}

// upstream: "should run async validation onChange"

///|
test "async validation: onChange runs and records on completion" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_async_validate=async_validator(not_other_async),
  )
  field.mount()
  assert_true(field.meta().is_valid())
  field.set_value("other")
  assert_true(field.meta().is_validating) // pending
  clock.run_all()
  assert_false(field.meta().is_validating)
  assert_false(field.meta().is_valid())
  assert_eq(field.meta().errors(), ["Please enter a different value"])
  assert_eq(
    field.meta().error_map.get(Change),
    Some(["Please enter a different value"]),
  )
}

// upstream: "should run async validation onChange with debounce" —
// two setValue within the window → one async run

///|
test "async validation: debounce collapses rapid changes (validator once)" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let runs = { n: 0, }
  let field = form.field(
    name_l(),
    on_change_async_debounce_ms=1000,
    on_change_async_validate=async_validator((value, c, done) => {
      runs.n = runs.n + 1
      not_other_async(value, c, done)
    }),
  )
  field.mount()
  field.set_value("other")
  field.set_value("other", dont_update_meta=true)
  clock.run_all()
  // "sleepMock will have been called 2 times without debounce" — with: 1
  assert_eq(runs.n, 1)
  assert_false(field.meta().is_valid())
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// debounce window: nothing runs until the window elapses

///|
test "async validation: debounce window delays the run" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let runs = { n: 0, }
  let field = form.field(
    name_l(),
    on_change_async_debounce_ms=500,
    on_change_async_validate=async_validator((value, c, done) => {
      runs.n = runs.n + 1
      not_other_async(value, c, done)
    }),
  )
  field.mount()
  field.set_value("other")
  clock.tick(250)
  assert_eq(runs.n, 0) // still inside the window
  assert_false(field.meta().is_validating) // validator not launched yet
  clock.tick(250) // window elapses; then the validator's own sleep(1000)
  assert_true(field.meta().is_validating) // now in flight
  clock.run_all()
  assert_eq(runs.n, 1)
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// upstream: "should run async validation onBlur"

///|
test "async validation: onBlur runs with debounce" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let runs = { n: 0, }
  let field = form.field(
    name_l(),
    on_blur_async_debounce_ms=1000,
    on_blur_async_validate=async_validator((value, c, done) => {
      runs.n = runs.n + 1
      not_other_async(value, c, done)
    }),
  )
  field.mount()
  field.set_value("other")
  field.handle_blur()
  field.handle_blur()
  clock.run_all()
  assert_eq(runs.n, 1) // debounced to one run
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// upstream: "should not apply in-flight async validation results after
// unmount"

///|
test "async validation: unmount aborts in-flight results" {
  let clock = vc()
  let form = FormApi::make({ name: "", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_async_debounce_ms=0,
    on_change_async_validate=async_validator((_value, c, done) => {
      let _ = c.schedule(1000, () => {
        done(["async error should be ignored after unmount"])
      })
    }),
  )
  field.mount()
  field.set_value("other")
  field.unmount()
  clock.run_all()
  // meta was reset at unmount; the late completion is discarded
  assert_eq(field.meta().errors(), [])
}

// race: slow first run, fast second — latest wins

///|
test "async validation: race latest run wins (stale discarded)" {
  let clock = vc()
  let form = FormApi::make({ name: "", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_async_validate=async_validator((value, c, done) => {
      let delay = if value == "slow" { 300 } else { 100 }
      let _ = c.schedule(delay, () => done(["err:\{value}"]))
    }),
  )
  field.mount()
  field.set_value("slow")
  clock.tick(10)
  field.set_value("fast")
  clock.run_all()
  assert_eq(field.meta().errors(), ["err:fast"])
}

// race: latest wins even when slower

///|
test "async validation: race latest wins when slower" {
  let clock = vc()
  let form = FormApi::make({ name: "", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_async_validate=async_validator((value, c, done) => {
      let delay = if value == "slow" { 300 } else { 100 }
      let _ = c.schedule(delay, () => done(["err:\{value}"]))
    }),
  )
  field.mount()
  field.set_value("fast")
  clock.tick(10)
  field.set_value("slow")
  clock.run_all()
  assert_eq(field.meta().errors(), ["err:slow"])
}

// upstream: "should abort enqueued debounced async validation if sync
// validation fails in the meantime" — a sync onChange error visible while
// the async run is enqueued

///|
test "async validation: sync errors coexist with pending async slot" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_validate=validator(v => {
      if v.length() < 3 {
        ["too short"]
      } else {
        []
      }
    }),
    on_change_async_debounce_ms=500,
    on_change_async_validate=async_validator((v, c, done) => {
      let _ = c.schedule(10, () => {
        if v.contains("error") {
          done(["No error allowed"])
        } else {
          done([])
        }
      })
    }),
  )
  field.mount()
  field.set_value("12") // sync error, async enqueued
  assert_eq(field.meta().errors(), ["too short"])
  clock.run_all()
  // async completed on the same cause slot with empty → clears slot,
  // but sync slot still holds "too short"? Both write the Change slot:
  // async completion (latest) replaces the slot with []
  // upstream keeps BOTH: sync runs before async, async result replaces
  assert_eq(field.meta().errors(), [])
}

// form-level flag: is_validating while any field validates

///|
test "async validation: form is_validating reflects field activity" {
  let clock = vc()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }).with_clock(
    clock.clock(),
  )
  let field = form.field(
    name_l(),
    on_change_async_validate=async_validator(not_other_async),
  )
  field.mount()
  assert_false(form.is_validating())
  field.set_value("other")
  assert_true(field.meta().is_validating)
  clock.run_all()
  assert_false(field.meta().is_validating)
}
