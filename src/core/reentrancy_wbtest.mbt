// Reentrancy audit: user code (onChange listeners, validators, subscriber
// callbacks) running inside core dispatch paths may mount/unmount fields and
// groups mid-flight. The dispatchers must iterate SNAPSHOT collections (lazy
// iteration over the live maps silently skips or repeats entries), dead
// instances must never record state (no phantom errors / validating flags),
// and cleanup paths must remove everything a registration owns.

///|
struct ReStep {
  retitle : String
} derive(Eq, Debug)

///|
pub extend ReStep with Debug::{to_repr}

///|
pub extend ReStep with Eq::{not_equal, equal}

///|
struct ReWizard {
  restep : ReStep
} derive(Eq, Debug)

///|
pub extend ReWizard with Debug::{to_repr}

///|
pub extend ReWizard with Eq::{not_equal, equal}

///|
fn re_step_l() -> Lens[ReWizard, ReStep] {
  field("step", (w : ReWizard) => w.restep, (_w, s) => { restep: s, })
}

///|
fn re_title_l() -> Lens[ReWizard, String] {
  re_step_l().compose(
    field("title", (s : ReStep) => s.retitle, (_s, t) => { retitle: t, }),
  )
}

///|
fn re_wizard_defaults() -> ReWizard {
  { restep: { retitle: "", }, }
}

///|
/// Mutable box: lets a group's own listeners reach the group handle
/// (defined after the group itself).
struct ReGroupBox {
  mut g : FormGroupApi[ReWizard, ReStep]?
}

// ---------------------------------------------------------------------------
// B6: mid-notify unmounts never land phantom state
// ---------------------------------------------------------------------------

///|
test "field async: unmounted mid-notify never lands phantom state" {
  let clock = VirtualClock::make()
  let form = FormApi::make(re_wizard_defaults()).with_clock(clock.clock())
  let f = form.field(
    re_title_l(),
    on_change_async_validate=async_validator((_v, _c, done) => done(["late"])),
    on_change_async_debounce_ms=0,
  )
  f.mount()
  // a subscriber unmounts the field when its Value change is notified
  let _ = form.subscribe_field(re_title_l().key, kinds=[Value], () => {
    f.unmount()
  })
  f.set_value("typed")
  clock.run_all()
  let m = form.field_meta(re_title_l().key)
  assert_false(m.is_validating)
  assert_false(m.has_errors())
}

///|
test "group: onChange listener unmounting the group skips its validation" {
  let form = FormApi::make(re_wizard_defaults())
  let box : ReGroupBox = { g: None, }
  let g = form.group(
    re_step_l(),
    on_change=_s => {
      match box.g {
        Some(x) => x.unmount()
        None => ()
      }
    },
    on_change_validate=group_validator_value(_s => {
      GroupValidationResult::group_error("boom")
    }),
  )
  box.g = Some(g)
  g.mount()
  // the write dispatches the group: its onChange listener unmounts it —
  // the change validation must NOT run afterwards (no phantom group error)
  form.set_value(re_title_l(), "typed")
  assert_eq(g.error_for_cause(Change), None)
}

// ---------------------------------------------------------------------------
// B7: reset aborts in-flight async validation (field + group)
// ---------------------------------------------------------------------------

///|
test "reset aborts in-flight field async validation" {
  let clock = VirtualClock::make()
  let form = FormApi::make(re_wizard_defaults()).with_clock(clock.clock())
  let f = form.field(
    re_title_l(),
    on_change_async_validate=async_validator((_v, c, done) => {
      let _ = c.schedule(50, () => done(["late"]))
    }),
    on_change_async_debounce_ms=0,
  )
  f.mount()
  f.set_value("typed")
  assert_true(form.field_meta(re_title_l().key).is_validating)
  form.reset()
  clock.run_all()
  let m = form.field_meta(re_title_l().key)
  assert_false(m.is_validating)
  assert_false(m.has_errors())
}

///|
test "reset aborts in-flight group async validation" {
  let clock = VirtualClock::make()
  let form = FormApi::make(re_wizard_defaults()).with_clock(clock.clock())
  let g = form.group(
    re_step_l(),
    on_change_async_validate=async_group_validator((_g, _v, c, done) => {
      let _ = c.schedule(50, () => {
        done(GroupValidationResult::group_error("late"))
      })
    }),
    on_change_async_debounce_ms=0,
  )
  g.mount()
  g.validate(Change)
  assert_true(g.is_validating())
  form.reset()
  clock.run_all()
  assert_eq(g.error_for_cause(Change), None)
  assert_false(g.is_validating())
}

// ---------------------------------------------------------------------------
// B5: snapshot iteration — mid-dispatch mutations never skip live entries
// ---------------------------------------------------------------------------

///|
struct ReLink {
  relink : String
  rexa : String
  reya : String
} derive(Eq, Debug)

///|
pub extend ReLink with Debug::{to_repr}

///|
pub extend ReLink with Eq::{not_equal, equal}

///|
fn re_link_l() -> Lens[ReLink, String] {
  field("link", (f : ReLink) => f.relink, (f, v) => { ..f, relink: v, })
}

///|
fn re_xa_l() -> Lens[ReLink, String] {
  field("xa", (f : ReLink) => f.rexa, (f, v) => { ..f, rexa: v, })
}

///|
fn re_ya_l() -> Lens[ReLink, String] {
  field("ya", (f : ReLink) => f.reya, (f, v) => { ..f, reya: v, })
}

///|
test "dep watches: mid-dispatch unmount never skips a live watcher" {
  let form = FormApi::make({ relink: "", rexa: "", reya: "", })
  // X and Y both listen to `link`; a subscriber unmounts Y the moment the
  // write is notified — BEFORE the watcher dispatch
  let fx = form.field(
    re_xa_l(),
    listen_to=[re_link_l().key],
    on_change_validate=validator(v => if v == "" { ["xa required"] } else { [] }),
  )
  let fy = form.field(
    re_ya_l(),
    listen_to=[re_link_l().key],
    on_change_validate=validator(v => if v == "" { ["ya required"] } else { [] }),
  )
  fx.mount()
  fy.mount()
  let _ = form.subscribe_field(re_link_l().key, kinds=[Value], () => {
    fy.unmount()
  })
  form.set_value(re_link_l(), "changed")
  // X's watch must have fired despite Y being unmounted mid-dispatch (the
  // watcher map was mutated while being dispatched)
  assert_true(form.field_meta(re_xa_l().key).has_errors())
  // the unmounted Y never validates — and its unmount cleaned any earlier
  // validation state
  assert_false(form.field_meta(re_ya_l().key).has_errors())
}

///|
test "form submit: mid-notify unmount never skips a sibling validator" {
  let form = FormApi::make({ relink: "", rexa: "", reya: "", })
  let runs : Array[String] = []
  let fa = form.field(
    re_xa_l(),
    on_submit_validate=validator_with_form((_v, _f) => {
      runs.push("a")
      ["a invalid"]
    }),
  )
  let fb = form.field(
    re_ya_l(),
    on_submit_validate=validator_with_form((_v, _f) => {
      runs.push("b")
      ["b invalid"]
    }),
  )
  fa.mount()
  fb.mount()
  form.set_value(re_link_l(), "touched")
  // the submit's notify_all unmounts B before the validator loop runs
  let _ = form.subscribe(() => fb.unmount())
  form.handle_submit()
  // A's validator ran exactly once; the unmounted B's never ran
  assert_eq(runs, ["a"])
  assert_true(form.field_meta(re_xa_l().key).has_errors())
  assert_false(form.field_meta(re_ya_l().key).has_errors())
}

// ---------------------------------------------------------------------------
// B8: group.set_value dispatches nested groups
// ---------------------------------------------------------------------------

///|
test "group set_value dispatches nested groups" {
  let form = FormApi::make(re_wizard_defaults())
  let inner_hits : Array[String] = []
  let inner_values : Array[String] = []
  let outer_hits : Array[String] = []
  let inner = form.group(
    re_title_l(),
    on_change=_t => inner_hits.push("inner"),
    on_change_validate=group_validator_value(t => {
      inner_values.push(t)
      GroupValidationResult::valid()
    }),
  )
  let outer = form.group(re_step_l(), on_change=_s => outer_hits.push("outer"))
  inner.mount()
  outer.mount()
  // an outer group write must dispatch the nested group's onChange listener
  // and change validation (the old path dispatched only the writing group)
  outer.set_value({ retitle: "typed", })
  assert_eq(inner_hits.length(), 1)
  assert_eq(inner_values, ["typed"])
  assert_eq(outer_hits.length(), 1)
}

// ---------------------------------------------------------------------------
// B9: unregister removes everything the registration owns
// ---------------------------------------------------------------------------

///|
test "unmounted field's submit validator never runs" {
  let form = FormApi::make({ relink: "", rexa: "", reya: "", })
  let runs : Array[String] = []
  let f = form.field(
    re_xa_l(),
    on_submit_validate=validator_with_form((_v, _f) => {
      runs.push("ran")
      []
    }),
  )
  f.mount()
  form.set_value(re_link_l(), "touched")
  f.unmount()
  form.handle_submit()
  // the stale validator must not run on later submissions
  assert_eq(runs.length(), 0)
}
