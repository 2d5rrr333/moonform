// Translated from form-core@1.33.5 packages/form-core/tests/FormGroupApi.spec.ts
// (31 it-cases; 26 translated, 5 exempted — the onDynamic/revalidateLogic
// plugin cases fall under deviation D-P3, 2 it.todo upstream). Upstream test
// names preserved in comments; groups are addressed by lens (the group's
// structured key is the child-field prefix), and `{group, fields}` validator
// returns map onto GroupValidationResult.

///|
struct Step {
  name : String
} derive(Eq, Debug)

///|
struct Wizard {
  step1 : Step
  step2 : Step
} derive(Eq, Debug)

///|
fn wizard_defaults() -> Wizard {
  { step1: { name: "test", }, step2: { name: "test2", }, }
}

///|
fn wizard_defaults_empty() -> Wizard {
  { step1: { name: "", }, step2: { name: "test2", }, }
}

///|
fn step1_l() -> Lens[Wizard, Step] {
  field("step1", w => w.step1, (w, s) => { ..w, step1: s, })
}

///|
fn step2_l() -> Lens[Wizard, Step] {
  field("step2", w => w.step2, (w, s) => { ..w, step2: s, })
}

///|
fn step_name_l() -> Lens[Step, String] {
  field("name", s => s.name, (_s, n) => { name: n, })
}

///|
fn step1_name_l() -> Lens[Wizard, String] {
  step1_l().compose(step_name_l())
}

///|
fn step2_name_l() -> Lens[Wizard, String] {
  step2_l().compose(step_name_l())
}

///|
fn step_name_required() -> GroupValidator[Step, Wizard] {
  group_validator_value(g => {
    if g.name == "" {
      GroupValidationResult::group_error("Name is required")
    } else {
      GroupValidationResult::valid()
    }
  })
}

///|
struct StepCell {
  mut step : Step?
}

///|
fn StepCell::make() -> StepCell {
  { step: None, }
}

///|
struct FlagCell {
  mut ok : Bool
}

///|
fn FlagCell::make() -> FlagCell {
  { ok: false, }
}

// upstream: "should allow a submission without submitting the form"

///|
test "group: submit runs on_group_submit without submitting the form" {
  let form = FormApi::make(wizard_defaults())
  let group_ran = { n: 0, }
  let step1 = form.group(step1_l())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(on_group_submit=(_v, _meta) => {
    group_ran.n = group_ran.n + 1
  })
  assert_eq(group_ran.n, 1)
  // the parent form never submitted
  assert_eq(form.submission_attempts(), 0)
  assert_false(form.is_submitting())
  assert_false(form.is_submitted())
}

// upstream: "should handle invalid submissions with form validator" — the
// form-level validator vehicle is expressed as the group's onSubmit
// validator distributing field errors (the v1 protocol has no separate
// form-level validator).

///|
test "group: submit invalid with distributed field errors" {
  let form = FormApi::make(wizard_defaults_empty())
  let group_ran = { n: 0, }
  let invalid_ran = { n: 0, }
  let step1 = form.group(
    step1_l(),
    on_submit_validate=group_validator_value(_g => {
      GroupValidationResult::fields([(Key::field("name"), "Name is required")])
    }),
  )
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(invalid_ran.n, 1)
  assert_eq(group_ran.n, 0)
  assert_eq(form.submission_attempts(), 0) // form.onSubmit never ran
}

// upstream: "should handle invalid submissions with form validator and
// throw away other unrelated fields errors" — group submission only
// validates fields under the group; fields outside stay untouched.

///|
test "group: submit scopes validation to fields under the group" {
  let form = FormApi::make(wizard_defaults_empty())
  let invalid_ran = { n: 0, }
  let step1 = form.group(step1_l())
  // both fields carry an onSubmit error (the "form validator" flagging
  // step1 and step2 alike); only step1's may surface from a step1 submit
  let name1 = form.field(
    step1_name_l(),
    on_submit_validate=validator(_v => ["Name is required"]),
  )
  let name2 = form.field(
    step2_name_l(),
    on_submit_validate=validator(_v => ["Name is required"]),
  )
  step1.mount()
  name1.mount()
  name2.mount()
  step1.handle_submit(on_group_submit_invalid=() => {
    invalid_ran.n = invalid_ran.n + 1
  })
  assert_eq(invalid_ran.n, 1)
  assert_true(name1.meta().has_errors()) // step1.name flagged
  assert_false(name2.meta().has_errors()) // unrelated step2.name untouched
}

// upstream: "Should handle validations on form groups themselves"

///|
test "group: onSubmit group validator sets the group error slot" {
  let form = FormApi::make(wizard_defaults_empty())
  let group_ran = { n: 0, }
  let invalid_ran = { n: 0, }
  let step1 = form.group(step1_l(), on_submit_validate=step_name_required())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(invalid_ran.n, 1)
  assert_eq(group_ran.n, 0)
  assert_eq(form.submission_attempts(), 0)
  assert_eq(step1.error_for_cause(Submit), Some(["Name is required"]))
}

// upstream: "should show onMount errors on form groups"

///|
test "group: onMount group validator errors surface at mount" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(step1_l(), on_mount_validate=step_name_required())
  step1.mount()
  assert_eq(step1.error_for_cause(Mount), Some(["Name is required"]))
  assert_eq(step1.errors(), ["Name is required"])
  assert_false(step1.is_group_valid())
  assert_false(step1.is_valid())
  assert_false(step1.can_submit())
}

// upstream: "should run listener onMount"

///|
test "group: onMount listener runs at mount with the group value" {
  let form = FormApi::make(wizard_defaults())
  let seen = StepCell::make()
  let step1 = form.group(step1_l(), on_mount=g => seen.step = Some(g))
  step1.mount()
  assert_eq(seen.step, Some({ name: "test", }))
}

// upstream: "should run listener onUnmount"

///|
test "group: onUnmount listener runs at unmount with the group value" {
  let form = FormApi::make(wizard_defaults())
  let seen = StepCell::make()
  let step1 = form.group(step1_l(), on_unmount=g => seen.step = Some(g))
  step1.mount()
  assert_true(seen.step is None)
  step1.unmount()
  assert_eq(seen.step, Some({ name: "test", }))
}

// upstream: "should run form onChangeGroup listener when a child field
// changes"

///|
test "group: form on_change_group fires on child field change" {
  let fired = { n: 0, }
  let group_key_hit = FlagCell::make()
  let form = FormApi::make(wizard_defaults_empty(), on_change_group=k => {
    fired.n = fired.n + 1
    if k == step1_l().key {
      group_key_hit.ok = true
    }
  })
  let step1 = form.group(step1_l())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  name_field.handle_change("test")
  assert_eq(fired.n, 1)
  assert_true(group_key_hit.ok) // fired with the group's key
}

// upstream: "should run group onChange listener when a child field changes"

///|
test "group: group on_change listener fires on child field change" {
  let form = FormApi::make(wizard_defaults_empty())
  let seen = StepCell::make()
  let step1 = form.group(step1_l(), on_change=g => seen.step = Some(g))
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  name_field.handle_change("test")
  assert_eq(seen.step, Some({ name: "test", }))
}

// upstream: "should debounce form onChange and onChangeGroup listeners
// independently when a child field changes"

///|
test "group: form on_change and on_change_group debounce independently" {
  let clock = VirtualClock::make()
  let change_fired = { n: 0, }
  let group_fired = { n: 0, }
  let form = FormApi::make(
    wizard_defaults_empty(),
    on_change=_k => change_fired.n = change_fired.n + 1,
    on_change_debounce_ms=100,
    on_change_group=_k => group_fired.n = group_fired.n + 1,
    on_change_group_debounce_ms=500,
  ).with_clock(clock.clock())
  let step1 = form.group(step1_l())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  name_field.handle_change("first")
  name_field.handle_change("second")
  assert_eq(change_fired.n, 0)
  assert_eq(group_fired.n, 0)
  clock.tick(100)
  assert_eq(change_fired.n, 1)
  assert_eq(group_fired.n, 0)
  clock.tick(400)
  assert_eq(group_fired.n, 1)
}

// upstream: "should only run form onChangeGroup when setting a group value"

///|
test "group: set_value fires only on_change_group, not on_change" {
  let clock = VirtualClock::make()
  let change_fired = { n: 0, }
  let group_fired = { n: 0, }
  let form = FormApi::make(
    wizard_defaults_empty(),
    on_change=_k => change_fired.n = change_fired.n + 1,
    on_change_debounce_ms=100,
    on_change_group=_k => group_fired.n = group_fired.n + 1,
    on_change_group_debounce_ms=100,
  ).with_clock(clock.clock())
  let step1 = form.group(step1_l())
  step1.mount()
  step1.set_value({ name: "test", })
  clock.tick(100)
  assert_eq(change_fired.n, 0) // form onChange did NOT fire
  assert_eq(group_fired.n, 1) // onChangeGroup fired once
}

// upstream: "should stop in-flight async group validation on unmount" —
// the abort signal maps to moonform's race guard (stale completions are
// discarded), same as the field-level async translations.

///|
test "group: unmount aborts in-flight async group validation" {
  let clock = VirtualClock::make()
  let form = FormApi::make(wizard_defaults()).with_clock(clock.clock())
  let async_check : AsyncGroupValidator[Step, Wizard] = async_group_validator((
    _g,
    _v,
    clock,
    done,
  ) => {
    let _ = clock.schedule(100, () => {
      done(GroupValidationResult::group_error("Name is invalid"))
    })
  })
  let step1 = form.group(
    step1_l(),
    on_change_async_validate=async_check,
    on_change_async_debounce_ms=0,
  )
  step1.mount()
  step1.validate(Change)
  assert_true(step1.is_validating()) // in flight
  step1.unmount()
  assert_false(step1.is_validating())
  clock.run_all()
  // the aborted run's completion is discarded: no group error recorded
  assert_eq(step1.error_for_cause(Change), None)
  // counterpart: without unmount the completion applies
  let form_b = FormApi::make(wizard_defaults()).with_clock(clock.clock())
  let step1b = form_b.group(
    step1_l(),
    on_change_async_validate=async_check,
    on_change_async_debounce_ms=0,
  )
  step1b.mount()
  step1b.validate(Change)
  clock.run_all()
  assert_eq(step1b.error_for_cause(Change), Some(["Name is invalid"]))
}

// upstream: "Should propagate onMount field errors from group validators to
// child fields" (upstream's errorSourceMap is subsumed by single-slot
// replace semantics — documented deviation D-P6)

///|
test "group: onMount field errors distribute to child fields" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(
    step1_l(),
    on_mount_validate=group_validator_value(_g => {
      GroupValidationResult::group_and_fields("Group is invalid", [
        (Key::field("name"), "Name is required"),
      ])
    }),
  )
  let name_field = form.field(step1_name_l())
  name_field.mount()
  step1.mount()
  assert_eq(step1.error_for_cause(Mount), Some(["Group is invalid"]))
  assert_eq(name_field.meta().error_map.get(Mount), Some(["Name is required"]))
  assert_false(step1.is_fields_valid())
  assert_false(step1.is_group_valid())
  assert_false(step1.is_valid())
}

///|
struct StepU {
  name : String
  unmounted_field : String
} derive(Eq, Debug)

///|
struct WizardU {
  step1 : StepU
  step2 : StepU
} derive(Eq, Debug)

///|
fn wizardu_step1_l() -> Lens[WizardU, StepU] {
  field("step1", w => w.step1, (w, s) => { ..w, step1: s, })
}

///|
fn stepu_unmounted_l() -> Lens[StepU, String] {
  field("unmountedField", s => s.unmounted_field, (s, u) => {
    ..s,
    unmounted_field: u,
  })
}

// upstream: "Should not throw when a group validator returns field errors
// for a field that is not mounted yet"

///|
test "group: distributing to a not-yet-mounted field is safe and defers" {
  let defaults : WizardU = {
    step1: { name: "", unmounted_field: "", },
    step2: { name: "test2", unmounted_field: "", },
  }
  let form = FormApi::make(defaults)
  let step1 = form.group(
    wizardu_step1_l(),
    on_mount_validate=group_validator_value(_g => {
      GroupValidationResult::fields([
        (Key::field("unmountedField"), "Unmounted field is required"),
      ])
    }),
  )
  // no FieldApi exists for step1.unmountedField: mount must not panic
  step1.mount()
  assert_false(step1.is_fields_valid())
  // once the field mounts, the distributed error surfaces on it
  let unmounted_field = form.field(
    wizardu_step1_l().compose(stepu_unmounted_l()),
  )
  unmounted_field.mount()
  assert_eq(
    unmounted_field.meta().error_map.get(Mount),
    Some(["Unmounted field is required"]),
  )
}

// upstream: "Should propagate manual function field errors from group
// validators to child fields"

///|
test "group: onSubmit field errors distribute to child fields" {
  let form = FormApi::make(wizard_defaults_empty())
  let group_ran = { n: 0, }
  let invalid_ran = { n: 0, }
  let step1 = form.group(
    step1_l(),
    on_submit_validate=group_validator_value(_g => {
      GroupValidationResult::fields([(Key::field("name"), "Name is required")])
    }),
  )
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(invalid_ran.n, 1)
  assert_eq(group_ran.n, 0)
  assert_eq(form.submission_attempts(), 0)
  assert_eq(name_field.meta().error_map.get(Submit), Some(["Name is required"]))
}

// upstream: "Should set the group error from a manual { group, fields }
// validator return"

///|
test "group: group_and_fields return sets both the group and field slots" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(
    step1_l(),
    on_submit_validate=group_validator_value(_g => {
      GroupValidationResult::group_and_fields("Group is invalid", [
        (Key::field("name"), "Name is required"),
      ])
    }),
  )
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit()
  assert_eq(step1.error_for_cause(Submit), Some(["Group is invalid"]))
  assert_eq(name_field.meta().error_map.get(Submit), Some(["Name is required"]))
}

// upstream: "Should not treat a manual { form, fields } return from a group
// validator as a group-level error" — the `form` key cannot be expressed in
// moonform's result type (structurally excluded); the equivalent assertion
// is that a fields-only return leaves the group slot untouched.

///|
test "group: fields-only return leaves the group slot untouched" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(
    step1_l(),
    on_submit_validate=group_validator_value(_g => {
      GroupValidationResult::fields([(Key::field("name"), "Name is required")])
    }),
  )
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit()
  assert_eq(step1.error_for_cause(Submit), None)
  assert_eq(step1.errors(), [])
  assert_eq(name_field.meta().error_map.get(Submit), Some(["Name is required"]))
}

// upstream: "Should propagate standard schema field errors from group
// validators to child fields" — the zod schema is expressed as a
// schema-style validator judging the group value (Resolver-equivalent
// translation, same as the standardSchemaValidator parity tests).

///|
test "group: schema-style validator distributes field errors" {
  let form = FormApi::make(wizard_defaults_empty())
  let group_ran = { n: 0, }
  let invalid_ran = { n: 0, }
  let step1 = form.group(
    step1_l(),
    on_submit_validate=group_validator_value(g => {
      let errs : Array[(Key, String)] = []
      if g.name.length() < 1 {
        errs.push((Key::field("name"), "Name is required"))
      }
      GroupValidationResult::fields(errs)
    }),
  )
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(invalid_ran.n, 1)
  assert_eq(group_ran.n, 0)
  assert_true(name_field.meta().error_map.get(Submit) is Some(_))
}

// upstream: "Should not duplicate field errors when overlapping schemas are
// attached to both the form and the group" — both writers flag the same
// field with the same issue; slots are replaced (not merged), so the
// field's errors array holds one entry.

///|
test "group: overlapping validators do not duplicate field errors" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(
    step1_l(),
    on_change_validate=group_validator_value(_g => {
      GroupValidationResult::fields([(Key::field("name"), "min 3")])
    }),
  )
  let name_field = form.field(
    step1_name_l(),
    on_change_validate=validator(_v => ["min 3"]),
  )
  step1.mount()
  name_field.mount()
  name_field.handle_change("")
  assert_eq(name_field.meta().errors().length(), 1)
  assert_true(name_field.meta().error_map.get(Change) is Some(_))
}

// upstream: "Should handle submit meta args" — meta is typed String
// (documented deviation from upstream's arbitrary meta object).

///|
test "group: submit meta flows to on_group_submit" {
  let form = FormApi::make(wizard_defaults())
  let seen_value = StepCell::make()
  let seen_meta = StrCell::make()
  let step1 = form.group(step1_l())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit(
    on_group_submit=(v, meta) => {
      seen_value.step = Some(v)
      seen_meta.v = meta
    },
    meta="button",
  )
  assert_eq(seen_value.step, Some({ name: "test", }))
  assert_eq(seen_meta.v, Some("button"))
  assert_eq(form.submission_attempts(), 0) // the form did not submit
}

// upstream: "should re-run validation on subsequent submissions after
// fixing the value"

///|
test "group: submit re-validates after the value is fixed" {
  let form = FormApi::make(wizard_defaults_empty())
  let group_ran = { n: 0, }
  let invalid_ran = { n: 0, }
  let step1 = form.group(step1_l(), on_submit_validate=step_name_required())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  // first submit fails
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(invalid_ran.n, 1)
  assert_eq(group_ran.n, 0)
  assert_eq(step1.error_for_cause(Submit), Some(["Name is required"]))
  // fix the value: second submit re-validates and succeeds
  name_field.set_value("valid name")
  step1.handle_submit(
    on_group_submit=(_v, _meta) => group_ran.n = group_ran.n + 1,
    on_group_submit_invalid=() => invalid_ran.n = invalid_ran.n + 1,
  )
  assert_eq(group_ran.n, 1)
  assert_eq(invalid_ran.n, 1)
  assert_eq(step1.error_for_cause(Submit), None)
}

// upstream: "group submissions should not bump the parent form-level
// submissionAttempts" (the onDynamic half of the upstream case is exempt
// under D-P3)

///|
test "group: submissions never bump the form's submission_attempts" {
  let defaults : Wizard = { step1: { name: "", }, step2: { name: "", }, }
  let form = FormApi::make(defaults)
  let step1 = form.group(step1_l())
  let name1 = form.field(step1_name_l())
  let name2 = form.field(step2_name_l())
  step1.mount()
  name1.mount()
  name2.mount()
  let before = form.submission_attempts()
  step1.handle_submit(on_group_submit=(_v, _meta) => ())
  assert_eq(form.submission_attempts(), before)
}

// upstream describe: "isFieldsValid / isGroupValid / isValid"
// case "should be true on a pristine, valid group"

///|
test "group: pristine valid group derives all-valid" {
  let form = FormApi::make(wizard_defaults())
  let step1 = form.group(step1_l())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  assert_true(step1.is_fields_valid())
  assert_true(step1.is_group_valid())
  assert_true(step1.is_valid())
}

// upstream case "isFieldsValid should be false when a child field has an
// error, while isGroupValid stays true"

///|
test "group: child field error flips is_fields_valid only" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(step1_l())
  let name_field = form.field(
    step1_name_l(),
    on_change_validate=validator(v => {
      if v == "" {
        ["Name is required"]
      } else {
        []
      }
    }),
  )
  step1.mount()
  name_field.mount()
  name_field.handle_change("")
  assert_true(name_field.meta().has_errors())
  assert_false(step1.is_fields_valid())
  assert_true(step1.is_group_valid())
  assert_false(step1.is_valid())
}

// upstream case "isGroupValid should be false when a group-level validator
// errors, while isFieldsValid stays true"

///|
test "group: group validator error flips is_group_valid only" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(step1_l(), on_submit_validate=step_name_required())
  let name_field = form.field(step1_name_l())
  step1.mount()
  name_field.mount()
  step1.handle_submit()
  assert_eq(step1.error_for_cause(Submit), Some(["Name is required"]))
  assert_true(step1.is_fields_valid())
  assert_false(step1.is_group_valid())
  assert_false(step1.is_valid())
}

// upstream case "isValid should recover to true after fixing both a
// field-level and group-level error"

///|
test "group: is_valid recovers after fixing field and group errors" {
  let form = FormApi::make(wizard_defaults_empty())
  let step1 = form.group(step1_l(), on_submit_validate=step_name_required())
  let name_field = form.field(
    step1_name_l(),
    on_change_validate=validator(v => {
      if v == "" {
        ["Name is required"]
      } else {
        []
      }
    }),
  )
  step1.mount()
  name_field.mount()
  name_field.handle_change("")
  step1.handle_submit()
  // the field-level branch is invalid (upstream asserts isFieldsValid and
  // isValid false; the group's own onSubmit also re-runs, keeping its slot
  // in sync — see handle_submit doc comment)
  assert_false(step1.is_fields_valid())
  assert_false(step1.is_valid())
  name_field.handle_change("valid name")
  step1.handle_submit()
  assert_true(step1.is_fields_valid())
  assert_true(step1.is_group_valid())
  assert_true(step1.is_valid())
}

///|
pub extend Step with Debug::{to_repr}

///|
pub extend Step with Eq::{not_equal, equal}

///|
pub extend StepU with Debug::{to_repr}

///|
pub extend StepU with Eq::{not_equal, equal}

///|
pub extend Wizard with Debug::{to_repr}

///|
pub extend Wizard with Eq::{not_equal, equal}

///|
pub extend WizardU with Debug::{to_repr}

///|
pub extend WizardU with Eq::{not_equal, equal}
