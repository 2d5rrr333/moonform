// Cross-field linkage + dynamic validator sets, translated from
// form-core@1.33.5 FieldApi.spec.ts onChangeListenTo tests and the
// dynamic-validation scenarios.

// upstream: "should run linked field validation" — a field re-validates
// when a field it listens to changes
///|
test "linkage: dependency change re-runs this field's onChange validation" {
  let form = FormApi::make({ name: "test", surname: "bar", age: 0, })
  // surname validator: invalid when it matches name
  let surname = form.field(
    surname_l(),
    on_change_validate=validator_with_form((s, person) => {
      if s == person.name {
        ["surname must differ from name"]
      } else {
        []
      }
    }),
    listen_to=[name_l().key],
  )
  surname.mount()
  assert_eq(surname.meta().errors().length(), 0) // bar != test
  // changing the DEPENDENCY re-runs the listener's validation
  form.set_value(name_l(), "bar") // now they match
  assert_eq(surname.meta().errors(), ["surname must differ from name"])
  form.set_value(name_l(), "foo")
  assert_eq(surname.meta().errors().length(), 0)
}

// a change in an unrelated field does not re-run the listener

///|
test "linkage: unrelated changes do not re-run" {
  let form = FormApi::make({ name: "a", surname: "b", age: 0, })
  let runs = { n: 0, }
  let surname = form.field(
    surname_l(),
    on_change_validate=validator(_ => {
      runs.n = runs.n + 1
      []
    }),
    listen_to=[name_l().key],
  )
  surname.mount()
  form.set_value(surname_l(), "x") // own change runs its validator
  assert_eq(runs.n, 1)
  form.set_value(person_age_l(), 30) // unrelated: no re-run
  assert_eq(runs.n, 1)
  form.set_value(name_l(), "y") // dependency: re-run
  assert_eq(runs.n, 2)
}

// upstream: unmount removes the dependency watch

///|
test "linkage: unmount stops dependency re-runs" {
  let form = FormApi::make({ name: "a", surname: "b", age: 0, })
  let runs = { n: 0, }
  let surname = form.field(
    surname_l(),
    on_change_validate=validator(_ => {
      runs.n = runs.n + 1
      []
    }),
    listen_to=[name_l().key],
  )
  surname.mount()
  form.set_value(name_l(), "x")
  assert_eq(runs.n, 1)
  surname.unmount()
  form.set_value(name_l(), "y")
  assert_eq(runs.n, 1) // watch removed with the field
}

// dynamic enable/disable: the validator set is chosen by the form state
// at run time (conditional validation), expressed by rebuilding the field
// with a different validator — the protocol stays pluggable

///|
test "dynamic validators: conditional enable via rebuild" {
  let form = FormApi::make({ name: "", surname: "", age: 0, })
  // phase 1: no validator — anything goes
  let plain = form.field(name_l())
  plain.mount()
  plain.set_value("x")
  assert_eq(plain.meta().errors().length(), 0)
  plain.unmount()
  // phase 2: validator enabled (e.g. checkbox toggled) — errors appear
  let guarded = form.field(
    name_l(),
    on_change_validate=validator(v => {
      if v.length() < 3 {
        ["min 3 chars"]
      } else {
        []
      }
    }),
  )
  guarded.mount()
  guarded.set_value("xy")
  assert_eq(guarded.meta().errors(), ["min 3 chars"])
  guarded.set_value("xyz")
  assert_eq(guarded.meta().errors().length(), 0)
}

// dynamic validation inside one validator via form access (cross-field
// condition): rule applies only when the sibling marks it relevant

///|
test "dynamic validators: rule active only when condition holds" {
  let form = FormApi::make({ name: "x", surname: "", age: 0, })
  // name must be >= 3 chars ONLY when surname is non-empty (e.g. an
  // optional section was opened)
  let name = form.field(
    name_l(),
    on_change_validate=validator_with_form((v, person) => {
      if person.surname.length() > 0 && v.length() < 3 {
        ["min 3 chars when surname set"]
      } else {
        []
      }
    }),
    listen_to=[surname_l().key],
  )
  name.mount()
  name.set_value("x")
  assert_eq(name.meta().errors().length(), 0) // surname empty: rule off
  form.set_value(surname_l(), "s") // condition turns on
  assert_eq(name.meta().errors(), ["min 3 chars when surname set"])
  name.set_value("xyz")
  assert_eq(name.meta().errors().length(), 0)
}
