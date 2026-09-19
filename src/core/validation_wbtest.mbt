// Validation trigger timing, translated from form-core@1.33.5
// FieldApi.spec.ts ("should run validation onChange/onBlur", onMount/
// onSubmit error display, "should not run onChange validation when onBlur
// is triggered", "should not toggle isValidating ...").

///|
fn not_other(value : String) -> Array[String] {
  if value == "other" {
    ["Please enter a different value"]
  } else {
    []
  }
}

// upstream: "should run validation onChange"

///|
test "validation: onChange runs and updates error slot" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l(), on_change_validate=validator(not_other))
  field.mount()
  assert_true(field.meta().is_valid())
  assert_eq(field.meta().errors().length(), 0)
  field.set_value("other")
  assert_false(field.meta().is_valid())
  assert_eq(field.meta().errors(), ["Please enter a different value"])
  // errorMap slot for onChange carries the error
  assert_eq(
    field.meta().error_map.get(Change),
    Some(["Please enter a different value"]),
  )
  field.set_value("nothing")
  assert_true(field.meta().is_valid())
  assert_eq(field.meta().errors().length(), 0)
}

// upstream: "should run validation onBlur"

///|
test "validation: onBlur runs when field is blurred" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l(), on_blur_validate=validator(not_other))
  field.mount()
  assert_eq(field.meta().errors().length(), 0)
  field.handle_blur()
  // default value "test" is fine — no error, but slot recorded as empty
  assert_eq(field.meta().errors().length(), 0)
  field.set_value("other")
  field.handle_blur()
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// upstream: "should not run onChange validation when onBlur is triggered"

///|
test "validation: blur does not trigger onChange validators" {
  let form = FormApi::make({ name: "other", surname: "", age: 0, })
  let change_ran = { n: 0, }
  let field = form.field(
    name_l(),
    on_change_validate=validator(_ => {
      change_ran.n = change_ran.n + 1
      []
    }),
  )
  field.mount()
  assert_eq(change_ran.n, 0)
  field.handle_blur()
  assert_eq(change_ran.n, 0) // blur never runs onChange validators
  field.set_value("x")
  assert_eq(change_ran.n, 1) // change does
}

// upstream: "should show onMount errors"

///|
test "validation: onMount errors appear immediately at mount" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l(), on_mount_validate=validator(not_other))
  field.mount()
  // default is "test" — valid; set default to the bad value to see error
  let form2 = FormApi::make({ name: "other", surname: "", age: 0, })
  let field2 = form2.field(name_l(), on_mount_validate=validator(not_other))
  field2.mount()
  assert_eq(field2.meta().errors(), ["Please enter a different value"])
  assert_false(field2.meta().is_valid())
}

// upstream: "should remove onMount errors on a field when its value changes"
// (FormApi.spec "should remove onMount error when the form is touched")

///|
test "validation: value change clears onMount errors" {
  let form = FormApi::make({ name: "other", surname: "", age: 0, })
  let field = form.field(name_l(), on_mount_validate=validator(not_other))
  field.mount()
  assert_true(field2_meta_has_mount_error(form))
  field.set_value("ok")
  // set_value clears the onMount slot by contract
  assert_eq(field.meta().error_map.get(Mount), None)
  assert_false(field2_meta_has_mount_error(form))
}

///|
fn field2_meta_has_mount_error(form : FormApi[Person]) -> Bool {
  match form.field_meta(name_l().key).error_map.get(Mount) {
    Some(_) => true
    None => false
  }
}

// upstream: "should show onSubmit errors" — submit-cause validators run
// via run_validation(Submit) (full submit orchestration is task 7.1)

///|
test "validation: onSubmit validators record into the submit slot" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l(), on_submit_validate=validator(not_other))
  field.mount()
  assert_eq(field.meta().errors().length(), 0)
  field.run_validation(Submit)
  assert_eq(field.meta().errors().length(), 0) // "test" is fine
  field.set_value("other")
  field.run_validation(Submit)
  assert_eq(field.meta().errors(), ["Please enter a different value"])
}

// upstream: "should not toggle isValidating when there are no async
// validators" — sync-only fields never enter the validating state
// (upstream issue #1130: no useless re-renders)

///|
test "validation: sync-only fields never set is_validating" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l(), on_change_validate=validator(not_other))
  field.mount()
  let observed : Array[Bool] = []
  let _id = form.subscribe_field(name_l().key, kinds=[Meta], () => {
    observed.push(form.field_meta(name_l().key).is_validating)
  })
  field.set_value("new value")
  // notifications may fire (error slot updates), but is_validating must
  // never have been true
  for state in observed {
    assert_false(state)
  }
  assert_false(field.meta().is_validating)
}

// cross-field validator sees the whole form value

///|
test "validation: cross-field validator reads sibling values" {
  let form = FormApi::make({ name: "foo", surname: "bar", age: 0, })
  // surname validator: invalid when name is "foo" and surname equals name
  let field = form.field(
    surname_l(),
    on_change_validate=validator_with_form((surname, person) => {
      if surname == person.name {
        ["surname must differ from name"]
      } else {
        []
      }
    }),
  )
  field.mount()
  form.set_value(surname_l(), "foo") // same as name
  assert_eq(field.meta().errors(), ["surname must differ from name"])
  form.set_value(surname_l(), "baz")
  assert_eq(field.meta().errors().length(), 0)
}

// combined validators run in order and concatenate errors

///|
test "validation: chained validators concatenate" {
  let form = FormApi::make({ name: "", surname: "", age: 0, })
  let nonempty : (String) -> Array[String] = v => {
    if v.length() == 0 {
      ["required"]
    } else {
      []
    }
  }
  let min3 : (String) -> Array[String] = v => {
    if v.length() < 3 {
      ["at least 3 characters"]
    } else {
      []
    }
  }
  let field = form.field(
    name_l(),
    on_change_validate=validator(nonempty).then(validator(min3)),
  )
  field.mount()
  field.set_value("ab")
  assert_eq(field.meta().errors(), ["at least 3 characters"])
  field.set_value("")
  assert_eq(field.meta().errors(), ["required", "at least 3 characters"])
}
