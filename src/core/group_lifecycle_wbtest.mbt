// Group lifecycle and dispatch-schedule blind spots: async validation's
// form-level submission gate, remount freshness, debounced async
// scheduling, and the group dispatch's snapshot semantics under mid-dispatch
// mount/unmount.

// ---------------------------------------------------------------------------
// async group validation gates FORM submission (upstream tracks one
// form-level isValidating across all async validators)
// ---------------------------------------------------------------------------

///|
test "group async: in-flight validation blocks form submission" {
  let clock = VirtualClock::make()
  let form = FormApi::make(wizard_defaults()).with_clock(clock.clock())
  let g = form.group(
    step1_l(),
    on_change_async_validate=async_group_validator((_gv, _v, c, done) => {
      let _ = c.schedule(50, () => done(GroupValidationResult::valid()))
    }),
  )
  g.mount()
  let f = form.field(step1_name_l())
  f.mount()
  // a write makes the form touched (can_submit's never-touched branch no
  // longer applies) and launches the group's async validation
  form.set_value(step1_name_l(), "typed")
  assert_true(g.is_validating()) // in flight (debounce 0)
  assert_false(form.can_submit()) // the in-flight group async blocks
  clock.run_all()
  assert_false(g.is_validating())
  assert_true(form.can_submit()) // nothing in flight, fields valid
}

// ---------------------------------------------------------------------------
// remount: a fresh lifecycle (upstream: every mount is a new FormGroupApi)
// ---------------------------------------------------------------------------

///|
test "group: remounting the same instance starts a fresh lifecycle" {
  let form = FormApi::make(wizard_defaults())
  let g = form.group(step1_l())
  g.mount()
  g.set_value({ name: "typed", }) // touched
  g.handle_submit() // attempts 1
  assert_eq(g.submission_attempts(), 1)
  assert_true(g.is_touched())
  g.unmount()
  g.mount() // same handle, new life: no inherited attempts/touched flag
  assert_eq(g.submission_attempts(), 0)
  assert_false(g.is_touched())
  assert_true(g.can_submit()) // never-touched branch again
}

// ---------------------------------------------------------------------------
// debounced group async: re-triggers inside the window reschedule (one run)
// ---------------------------------------------------------------------------

///|
test "group async: debounce window reschedules, fires exactly once" {
  let clock = VirtualClock::make()
  let form = FormApi::make(wizard_defaults()).with_clock(clock.clock())
  let runs = { n: 0, }
  let g = form.group(
    step1_l(),
    on_change_async_validate=async_group_validator((_gv, _v, c, done) => {
      runs.n = runs.n + 1
      let _ = c.schedule(30, () => {
        done(GroupValidationResult::group_error("late"))
      })
    }),
    on_change_async_debounce_ms=10,
  )
  g.mount()
  g.validate(Change) // debounce timer due at t=10
  clock.tick(5)
  assert_false(g.is_validating()) // still inside the window
  g.validate(Change) // re-trigger: the first timer is cancelled, due t=15
  clock.tick(5) // t=10 — the cancelled timer never fires
  assert_false(g.is_validating())
  clock.tick(5) // t=15 — fires: launch, validator schedules done at t=45
  assert_true(g.is_validating())
  assert_eq(runs.n, 1)
  clock.tick(30) // t=45 — completion applies
  assert_false(g.is_validating())
  assert_eq(runs.n, 1) // one run, one application
  assert_eq(g.error_for_cause(Change), Some(["late"]))
}

// ---------------------------------------------------------------------------
// dispatch snapshot: mid-dispatch mount/unmount of groups
// ---------------------------------------------------------------------------

///|
struct WizRootCell {
  mut g : FormGroupApi[Wizard, Wizard]?
}

///|
struct WizStepCell {
  mut g : FormGroupApi[Wizard, Step]?
}

///|
test "group dispatch: self-unmount mid-loop leaves siblings dispatched" {
  let form = FormApi::make(wizard_defaults())
  let root_hits = { n: 0, }
  let cell : WizRootCell = { g: None, }
  let root = form.group(identity(), on_change=_v => {
    root_hits.n = root_hits.n + 1
    match cell.g {
      Some(x) => x.unmount() // self-unmount mid-dispatch
      None => ()
    }
  })
  cell.g = Some(root)
  let name_hits = { n: 0, }
  let name_g = form.group(step1_l(), on_change=_g => {
    name_hits.n = name_hits.n + 1
  })
  root.mount()
  name_g.mount()
  // the write dispatches both groups; the root group unmounts itself in
  // its own dispatch — the sibling must still dispatch (snapshot + liveness)
  form.set_value(step1_name_l(), "typed")
  assert_eq(root_hits.n, 1)
  assert_eq(name_hits.n, 1)
  // the root group is gone: the next write reaches only the sibling
  form.set_value(step1_name_l(), "again")
  assert_eq(root_hits.n, 1)
  assert_eq(name_hits.n, 2)
}

///|
test "group dispatch: a group mounted mid-dispatch gets no in-flight event" {
  let form = FormApi::make(wizard_defaults())
  let late_hits = { n: 0, }
  let armed = { n: 0, }
  let late_cell : WizStepCell = { g: None, }
  // only the root group is mounted when the write happens; its onChange
  // mounts a group at step1 — the in-flight dispatch iterates its
  // snapshot, so the new group receives nothing for THIS event
  let _root = form.group(identity(), on_change=_v => {
    if armed.n == 0 {
      armed.n = 1
      match late_cell.g {
        Some(x) => x.mount()
        None => ()
      }
    }
  })
  let late_g = form.group(step1_l(), on_change=_g => {
    late_hits.n = late_hits.n + 1
  })
  late_cell.g = Some(late_g)
  _root.mount()
  form.set_value(step1_name_l(), "typed")
  assert_eq(late_hits.n, 0) // not in the dispatch snapshot
  form.set_value(step1_name_l(), "again")
  assert_eq(late_hits.n, 1) // the next event reaches it
}
