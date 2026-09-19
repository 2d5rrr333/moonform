// Translated from form-core@1.33.5 packages/form-core/tests/FormApi.spec.ts
// (lifecycle subset: default state, update, reset, field values, dirty).
// Upstream test names preserved; dot-path accessors become lenses.

///|
struct Person {
  name : String
  surname : String
  age : Int
} derive(Eq, Debug)

///|
fn person_defaults() -> Person {
  { name: "test", surname: "test2", age: 30, }
}

///|
fn name_l() -> Lens[Person, String] {
  field("name", p => p.name, (p, n) => { ..p, name: n, })
}

///|
fn surname_l() -> Lens[Person, String] {
  field("surname", p => p.surname, (p, s) => { ..p, surname: s, })
}

///|
fn person_age_l() -> Lens[Person, Int] {
  field("age", p => p.age, (p, a) => { ..p, age: a, })
}

// upstream: "should get default form state when default values are passed"

///|
test "form api: default state from default values" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  assert_eq(form.values(), { name: "test", surname: "", age: 0, })
  assert_false(form.is_dirty())
  assert_false(form.is_touched())
  assert_false(form.is_submitting())
  assert_eq(form.submission_attempts(), 0)
}

// upstream: "should get default form state when default state is passed"

///|
test "form api: default state from default_state" {
  let ds : FormDefaultState[Person] = {
    ..FormDefaultState::make(),
    submission_attempts: 30,
  }
  let form = FormApi::make(person_defaults(), default_state=ds)
  assert_eq(form.submission_attempts(), 30)
}

// upstream: "should handle updating form state"

///|
test "form api: update replaces defaults and state (untouched form)" {
  let form = FormApi::make(person_defaults())
  form.update(default_values={ name: "other", surname: "test2", age: 30, }, default_state={
    ..FormDefaultState::make(),
    submission_attempts: 300,
  })
  assert_eq(form.values().name, "other")
  assert_eq(form.submission_attempts(), 300)
}

// upstream: "should reset the form state properly"

///|
test "form api: reset restores values and clears lifecycle" {
  let form = FormApi::make(person_defaults())
  form.set_value(name_l(), "other", dont_update_meta=true)
  form.submission_attempts = 300 // simulate submitted state
  form.reset()
  assert_eq(form.values(), person_defaults())
  assert_false(form.has_field_meta(name_l().key)) // never meta-touched
  assert_eq(form.submission_attempts(), 0)
}

// upstream: "should reset with provided custom default values"

///|
test "form api: reset with custom default values" {
  let form = FormApi::make(person_defaults())
  form.set_value(name_l(), "other")
  assert_eq(form.values(), { name: "other", surname: "test2", age: 30, })
  form.reset()
  assert_eq(form.values(), person_defaults())
  form.set_value(name_l(), "other2")
  form.set_value(person_age_l(), 33)
  let reset_values : Person = {
    name: "reset name",
    age: 40,
    surname: "reset surname",
  }
  form.reset(values=reset_values)
  assert_eq(form.values(), reset_values)
}

// upstream: "should reset and set the new default values that are restored
// after an empty reset"

///|
test "form api: empty reset restores the new defaults" {
  let form = FormApi::make({ name: "initial", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  form.reset(values={ name: "other", surname: "", age: 0, })
  assert_eq(form.values().name, "other")
  field.handle_change("")
  form.reset()
  assert_eq(form.values().name, "other")
}

// upstream: "should reset without setting the new default values ... if
// opts.keepDefaultValues is true"

///|
test "form api: keep_default_values keeps original defaults" {
  let form = FormApi::make({ name: "initial", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  form.reset(
    values={ name: "other", surname: "", age: 0, },
    keep_default_values=true,
  )
  assert_eq(form.values().name, "other")
  field.handle_change("")
  form.reset()
  assert_eq(form.values().name, "initial")
}

// upstream: "should prioritize field-level defaultValue over form-level
// defaultValues on reset"

///|
test "form api: field-level default wins on reset" {
  let form = FormApi::make({ name: "form-default", surname: "", age: 25, })
  let name_field = form.field(name_l(), default="field-default")
  name_field.mount()
  let age_field = form.field(person_age_l())
  age_field.mount()
  name_field.set_value("changed-name")
  age_field.set_value(30)
  assert_eq(form.values().name, "changed-name")
  assert_eq(form.values().age, 30)
  form.reset()
  assert_eq(form.values().name, "field-default") // field's default
  assert_eq(form.values().age, 25) // form's default
}

// upstream: "should handle multiple fields with mixed mount states"

///|
test "form api: field meta exists only for mounted fields" {
  let form = FormApi::make({ name: "", surname: "", age: 0, })
  let first = form.field(name_l())
  first.mount()
  assert_true(form.has_field_meta(name_l().key))
  assert_false(form.has_field_meta(surname_l().key))
  let last = form.field(surname_l())
  last.mount()
  assert_true(form.has_field_meta(surname_l().key))
}

// upstream: "should get a field's value"

///|
test "form api: get field value" {
  let form = FormApi::make(person_defaults())
  assert_eq(form.get_value(name_l()), "test")
}

// upstream: "should set a field's value"

///|
test "form api: set field value" {
  let form = FormApi::make(person_defaults())
  form.set_value(name_l(), "other")
  assert_eq(form.get_value(name_l()), "other")
}

// upstream: "should be dirty after a field's value has been set"

///|
test "form api: dirty after set, touched recorded" {
  let form = FormApi::make(person_defaults())
  form.set_value(name_l(), "other")
  assert_true(form.is_dirty())
  assert_false(form.is_pristine())
  assert_true(form.is_touched())
  assert_true(form.field_meta(name_l().key).is_touched)
}

// upstream: "should be clean again after being reset from a dirty state"

///|
test "form api: clean again after reset from dirty state" {
  let form = FormApi::make(person_defaults())
  form.set_value(name_l(), "other")
  assert_true(form.is_dirty())
  form.reset()
  assert_false(form.is_dirty())
  assert_true(form.is_pristine())
}

// value semantics companion: writing through the form never mutates the
// original defaults value

///|
test "form api: writes keep the original defaults intact" {
  let defaults = person_defaults()
  let form = FormApi::make(defaults)
  form.set_value(name_l(), "other")
  assert_eq(defaults.name, "test") // original struct untouched
  assert_eq(form.default_values().name, "test")
}
