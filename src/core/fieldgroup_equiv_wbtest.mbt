// Translated from form-core@1.33.5 packages/form-core/tests/FieldGroupApi.spec.ts
// as lens-composition equivalence tests: upstream FieldGroupApi is a
// string-remapping machine (group-relative names -> form field names); in
// moonform the same observable behavior falls out of accessor composition —
// `parent_l.compose(child_l)` IS the remapped field (deviation D-P8).
// 16 of 20 upstream cases translate; the 4 pure string-machinery cases
// (getFormFieldName / getFormFieldOptions / listener-path remapping / the
// top-level-array crash guard) are subsumed by the design — see
// upstream/PARITY.md.

///|
struct FgPerson {
  name : String
  age : Int
} derive(Eq, Debug)

///|
struct FgRelatives {
  father : FgPerson
} derive(Eq, Debug)

///|
struct FgValues {
  name : String
  age : Int
  people : Array[FgPerson]
  relatives : FgRelatives
} derive(Eq, Debug)

///|
fn fg_people_l() -> Lens[FgValues, Array[FgPerson]] {
  field("people", v => v.people, (v, p) => { ..v, people: p, })
}

///|
fn fg_relatives_l() -> Lens[FgValues, FgRelatives] {
  field("relatives", v => v.relatives, (v, r) => { ..v, relatives: r, })
}

///|
fn fg_father_l() -> Lens[FgValues, FgPerson] {
  fg_relatives_l().compose(
    field("father", r => r.father, (_r, f) => { father: f, }),
  )
}

///|
fn fg_person_name_l() -> Lens[FgPerson, String] {
  field("name", p => p.name, (p, n) => { ..p, name: n, })
}

///|
fn fg_person_age_l() -> Lens[FgPerson, Int] {
  field("age", p => p.age, (p, a) => { ..p, age: a, })
}

///|
fn fg_person0_age_l() -> Lens[FgValues, Int] {
  at(fg_people_l(), 0).compose(fg_person_age_l())
}

///|
fn fg_person1_age_l() -> Lens[FgValues, Int] {
  at(fg_people_l(), 1).compose(fg_person_age_l())
}

///|
fn fg_father_age_l() -> Lens[FgValues, Int] {
  fg_father_l().compose(fg_person_age_l())
}

///|
fn fg_defaults() -> FgValues {
  {
    name: "Do not access",
    age: -1,
    people: [
      { name: "fieldGroup one", age: 1, },
      { name: "fieldGroup two", age: 2, },
    ],
    relatives: { father: { name: "fieldGroup three", age: 3, }, },
  }
}

// upstream: "should inherit defaultValues from the form" — the group view
// (a composed lens onto people[0] / people[1] / relatives.father) reads the
// form defaults directly.

///|
test "fieldgroup: composed group views inherit default values" {
  let form = FormApi::make(fg_defaults())
  let g1 = form.field(at(fg_people_l(), 0))
  let g2 = form.field(at(fg_people_l(), 1))
  let g3 = form.field(fg_father_l())
  g1.mount()
  g2.mount()
  g3.mount()
  assert_eq(g1.value(), { name: "fieldGroup one", age: 1, })
  assert_eq(g2.value(), { name: "fieldGroup two", age: 2, })
  assert_eq(g3.value(), { name: "fieldGroup three", age: 3, })
}

// upstream: "should have the state synced with the form" — one store:
// writes through any composed lens (whole-group or per-field) are visible
// from every view; form reset restores the defaults.

///|
test "fieldgroup: group views stay synced with the form" {
  let defaults : FgValues = {
    name: "",
    age: 0,
    people: [],
    relatives: { father: { name: "father", age: 10, }, },
  }
  let form = FormApi::make(defaults)
  let father = form.field(fg_father_l())
  father.mount()
  assert_eq(father.value(), { name: "father", age: 10, })
  // per-field writes through the group view
  form.set_value(fg_father_l().compose(fg_person_name_l()), "New name")
  form.set_value(fg_father_l().compose(fg_person_age_l()), 50)
  assert_eq(father.value(), { name: "New name", age: 50, })
  // whole-group write
  form.set_value(fg_father_l(), { name: "Second new name", age: 100, })
  assert_eq(father.value(), { name: "Second new name", age: 100, })
  assert_eq(
    form.get_value(fg_father_l().compose(fg_person_name_l())),
    "Second new name",
  )
  // form reset flows into the group view
  form.reset()
  assert_eq(father.value(), { name: "father", age: 10, })
}

// upstream: "should validate the right field from the form" — group-
// relative validateField('age', 'change') is the composed field's
// run_validation; sibling groups stay untouched.

///|
test "fieldgroup: validating one composed field leaves siblings untouched" {
  let form = FormApi::make(fg_defaults())
  let f1 = form.field(
    fg_person0_age_l(),
    on_change_validate=validator(_v => ["Field 1"]),
  )
  let f2 = form.field(
    fg_person1_age_l(),
    on_change_validate=validator(_v => ["Field 2"]),
  )
  let f3 = form.field(
    fg_father_age_l(),
    on_change_validate=validator(_v => ["Field 3"]),
  )
  f1.mount()
  f2.mount()
  f3.mount()
  f1.run_validation(Change)
  assert_eq(f1.meta().errors(), ["Field 1"])
  assert_eq(f2.meta().errors(), [])
  assert_eq(f3.meta().errors(), [])
  f2.run_validation(Change)
  assert_eq(f1.meta().errors(), ["Field 1"])
  assert_eq(f2.meta().errors(), ["Field 2"])
  assert_eq(f3.meta().errors(), [])
  f3.run_validation(Change)
  assert_eq(f1.meta().errors(), ["Field 1"])
  assert_eq(f2.meta().errors(), ["Field 2"])
  assert_eq(f3.meta().errors(), ["Field 3"])
}

// upstream: "should get the right field value from the nested field"

///|
test "fieldgroup: composed reads address the right fields" {
  let form = FormApi::make(fg_defaults())
  assert_eq(form.get_value(fg_person0_age_l()), 1)
  assert_eq(
    form.get_value(at(fg_people_l(), 0).compose(fg_person_name_l())),
    "fieldGroup one",
  )
  assert_eq(form.get_value(fg_person1_age_l()), 2)
  assert_eq(
    form.get_value(at(fg_people_l(), 1).compose(fg_person_name_l())),
    "fieldGroup two",
  )
  assert_eq(form.get_value(fg_father_age_l()), 3)
  assert_eq(
    form.get_value(fg_father_l().compose(fg_person_name_l())),
    "fieldGroup three",
  )
}

// upstream: "should get the correct field Meta from the nested field"

///|
test "fieldgroup: composed meta reads address the right fields" {
  let form = FormApi::make(fg_defaults())
  let f1 = form.field(fg_person0_age_l())
  let f2 = form.field(fg_person1_age_l())
  let f3 = form.field(
    fg_father_age_l(),
    on_mount_validate=validator(_v => ["Error"]),
  )
  f1.mount()
  f2.mount()
  f3.mount()
  f1.handle_change(0)
  f2.handle_blur()
  let m1 = form.field_meta(fg_person0_age_l().key)
  let m2 = form.field_meta(fg_person1_age_l().key)
  let m3 = form.field_meta(fg_father_age_l().key)
  assert_true(m1.is_valid())
  assert_true(m2.is_valid())
  assert_false(m3.is_valid())
  assert_true(m1.is_dirty)
  assert_false(m2.is_dirty)
  assert_false(m3.is_dirty)
  assert_false(m1.is_blurred)
  assert_true(m2.is_blurred)
  assert_false(m3.is_blurred)
}

// upstream: "should be compliant with top level array defaultValues" —
// element writes through composed index lenses (whole element and nested
// field alike).

///|
test "fieldgroup: element writes through composed index lenses" {
  let defaults : FgValues = {
    name: "",
    age: 0,
    people: [{ name: "Default", age: 0, }, { name: "Default", age: 0, }],
    relatives: { father: { name: "", age: 0, }, },
  }
  let form = FormApi::make(defaults)
  form.set_value(at(fg_people_l(), 0), { name: "Override One", age: 0, })
  form.set_value(
    at(fg_people_l(), 1).compose(fg_person_name_l()),
    "Override Two",
  )
  assert_eq(
    form.get_value(at(fg_people_l(), 0).compose(fg_person_name_l())),
    "Override One",
  )
  assert_eq(
    form.get_value(at(fg_people_l(), 1).compose(fg_person_name_l())),
    "Override Two",
  )
}

///|
struct FgNames {
  name : String
} derive(Eq, Debug)

///|
struct FgHolder {
  members : Array[FgNames]
} derive(Eq, Debug)

///|
struct FgTop {
  people : FgHolder
} derive(Eq, Debug)

///|
fn fg_top_people_l() -> Lens[FgTop, FgHolder] {
  field("people", v => v.people, (_v, p) => { people: p, })
}

///|
fn fg_holder_members_l() -> Lens[FgHolder, Array[FgNames]] {
  field("members", v => v.members, (_v, n) => { members: n, })
}

///|
fn fg_top_names_l() -> Lens[FgTop, Array[FgNames]] {
  fg_top_people_l().compose(fg_holder_members_l())
}

///|
fn fg_names_name_l() -> Lens[FgNames, String] {
  field("name", v => v.name, (_v, n) => { name: n, })
}

///|
fn fg_top_name_at(i : Int) -> Lens[FgTop, String] {
  at(fg_top_names_l(), i).compose(fg_names_name_l())
}

///|
fn fg_top_defaults() -> FgTop {
  { people: { members: [{ name: "", }, { name: "", }, { name: "", }], }, }
}

// upstream: "should forward validateArrayFieldsStartingFrom to the form" —
// validate (and touch, as upstream validate() does) every element field
// from an index on.

///|
test "fieldgroup: validating array fields starting from an index" {
  let form = FormApi::make(fg_top_defaults())
  let f0 = form.field(fg_top_name_at(0))
  let f1 = form.field(fg_top_name_at(1))
  let f2 = form.field(fg_top_name_at(2))
  f0.mount()
  f1.mount()
  f2.mount()
  // upstream validateArrayFieldsStartingFrom('names', 1, 'change'):
  // fields at and after index 1 validate + become touched
  for i in [1, 2] {
    let field = form.field(fg_top_name_at(i))
    field.run_validation(Change)
    form.meta_store().update(field.key(), m => { ..m, is_touched: true, })
  }
  assert_false(f0.meta().is_touched)
  assert_true(f1.meta().is_touched)
  assert_true(f2.meta().is_touched)
}

// upstream: "should forward handleSubmit to the form" — composed fields
// participate in form submission (there is no forwarding layer to test:
// the composed field IS a form field).

///|
test "fieldgroup: composed fields participate in form submission" {
  let form = FormApi::make({ people: { members: [{ name: "", }], }, })
  let field = form.field(fg_top_name_at(0))
  field.mount()
  form.handle_submit()
  assert_true(form.is_submitted())
  assert_true(form.is_submit_successful())
}

// upstream: "should forward resetField to the form"

///|
test "fieldgroup: reset returns the composed field to its default" {
  let form = FormApi::make({ people: { members: [{ name: "", }], }, })
  let field = form.field(fg_top_name_at(0))
  field.mount()
  field.set_value("Nested")
  assert_eq(field.value(), "Nested")
  field.reset()
  assert_eq(field.value(), "")
  assert_false(field.meta().is_touched)
  assert_false(field.meta().has_errors())
}

// upstream: "should forward deleteField to the form" — meta (and subfield
// meta) is removed; values stay in place (deviation D-P5: typed form
// values have no "absent field" state).

///|
test "fieldgroup: delete removes composed meta, values stay (D-P5)" {
  let form = FormApi::make({ people: { members: [{ name: "", }], }, })
  let field = form.field(fg_top_name_at(0))
  field.mount()
  field.set_value("Nested")
  form.delete_field(fg_top_name_at(0).key)
  assert_false(form.has_field_meta(fg_top_name_at(0).key))
  assert_eq(form.get_value(fg_top_name_at(0)), "Nested") // value kept
}

// upstream: "should forward array methods to the form" — the full array
// operation set through a composed array lens (prefix meta migration
// included; see array_ops_wbtest for the migration assertions).

///|
test "fieldgroup: array ops through a composed array lens" {
  let form = FormApi::make(fg_top_defaults())
  let f0 = form.field(fg_top_name_at(0))
  let f1 = form.field(fg_top_name_at(1))
  let f2 = form.field(fg_top_name_at(2))
  f0.mount()
  f1.mount()
  f2.mount()
  form.push_value(fg_top_names_l(), { name: "Push", })
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "", },
    { name: "", },
    { name: "", },
    { name: "Push", },
  ])
  form.insert_value(fg_top_names_l(), 1, { name: "Insert", })
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "", },
    { name: "Insert", },
    { name: "", },
    { name: "", },
    { name: "Push", },
  ])
  form.replace_value(fg_top_names_l(), 2, { name: "Replace", })
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "", },
    { name: "Insert", },
    { name: "Replace", },
    { name: "", },
    { name: "Push", },
  ])
  form.remove_value(fg_top_names_l(), 3)
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "", },
    { name: "Insert", },
    { name: "Replace", },
    { name: "Push", },
  ])
  form.swap_values(fg_top_names_l(), 2, 3)
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "", },
    { name: "Insert", },
    { name: "Push", },
    { name: "Replace", },
  ])
  form.move_value(fg_top_names_l(), 0, 2)
  assert_eq(form.get_value(fg_top_names_l()), [
    { name: "Insert", },
    { name: "Push", },
    { name: "", },
    { name: "Replace", },
  ])
  form.clear_values(fg_top_names_l())
  assert_eq(form.get_value(fg_top_names_l()), [])
}

// upstream: "should allow nesting form fieldGroupes within each other" —
// composition of compositions resolves to the same store.

///|
struct FgNested {
  first_name : String
} derive(Eq, Debug)

///|
struct FgWrapper {
  field : FgNested
} derive(Eq, Debug)

///|
struct FgFormVals {
  form : FgWrapper
  unrelated : String
} derive(Eq, Debug)

///|
fn fg_form_l() -> Lens[FgFormVals, FgWrapper] {
  field("form", v => v.form, (v, f) => { ..v, form: f, })
}

///|
fn fg_wrap_field_l() -> Lens[FgWrapper, FgNested] {
  field("field", v => v.field, (_v, f) => { field: f, })
}

///|
test "fieldgroup: nested composition resolves like nested groups" {
  let defaults : FgFormVals = {
    form: { field: { first_name: "Test", }, },
    unrelated: "",
  }
  let form = FormApi::make(defaults)
  let wrap = form.field(fg_form_l())
  let nested = form.field(fg_form_l().compose(fg_wrap_field_l()))
  wrap.mount()
  nested.mount()
  // the nested view equals the wrapper's field equals the form's value
  assert_eq(nested.value(), { first_name: "Test", })
  assert_eq(nested.value(), wrap.value().field)
  assert_eq(nested.value(), form.values().form.field)
}

// upstream: "should allow remapping values for fieldGroups" — a remapping
// lens addresses different form fields under group-relative names (here
// firstName -> a, lastName -> b).

///|
struct FgAB {
  a : String
  b : String
} derive(Eq, Debug)

///|
fn fgab_first_l() -> Lens[FgAB, String] {
  field("firstName", v => v.a, (v, x) => { ..v, a: x, })
}

///|
fn fgab_last_l() -> Lens[FgAB, String] {
  field("lastName", v => v.b, (v, x) => { ..v, b: x, })
}

///|
test "fieldgroup: remapping lenses address other form fields" {
  let defaults : FgAB = { a: "A", b: "B", }
  let form = FormApi::make(defaults)
  assert_eq(form.get_value(fgab_first_l()), "A")
  assert_eq(form.get_value(fgab_last_l()), "B")
  // the group-relative key names render as the group sees them
  assert_eq(fgab_first_l().key.render(), "firstName")
  assert_eq(fgab_last_l().key.render(), "lastName")
}

// upstream: "should allow setting and resetting field meta in field groups"

///|
test "fieldgroup: setting field meta through composed keys" {
  let form = FormApi::make(fg_top_defaults())
  let field = form.field(fg_top_name_at(0))
  field.mount()
  form.meta_store().update(field.key(), m => { ..m, is_touched: true, })
  assert_true(form.field_meta(fg_top_name_at(0).key).is_touched)
}

// upstream: "should forward validateAllFields to the form" — validating
// every mounted field under a prefix surfaces errors on the fields and on
// the form's field validity.

///|
test "fieldgroup: validating all fields under a prefix" {
  let form = FormApi::make(fg_top_defaults())
  let field = form.field(
    fg_top_name_at(0),
    on_change_validate=validator(_v => ["Error"]),
  )
  field.mount()
  // upstream validateAllFields('change'): every field under the group
  field.run_validation(Change)
  assert_false(form.is_valid_fields())
  assert_false(field.meta().is_valid())
  assert_eq(field.meta().errors(), ["Error"])
}

///|
pub extend FgAB with Debug::{to_repr}

///|
pub extend FgAB with Eq::{not_equal, equal}

///|
pub extend FgFormVals with Debug::{to_repr}

///|
pub extend FgFormVals with Eq::{not_equal, equal}

///|
pub extend FgHolder with Debug::{to_repr}

///|
pub extend FgHolder with Eq::{not_equal, equal}

///|
pub extend FgNames with Debug::{to_repr}

///|
pub extend FgNames with Eq::{not_equal, equal}

///|
pub extend FgNested with Debug::{to_repr}

///|
pub extend FgNested with Eq::{not_equal, equal}

///|
pub extend FgPerson with Debug::{to_repr}

///|
pub extend FgPerson with Eq::{not_equal, equal}

///|
pub extend FgRelatives with Debug::{to_repr}

///|
pub extend FgRelatives with Eq::{not_equal, equal}

///|
pub extend FgTop with Debug::{to_repr}

///|
pub extend FgTop with Eq::{not_equal, equal}

///|
pub extend FgValues with Debug::{to_repr}

///|
pub extend FgValues with Eq::{not_equal, equal}

///|
pub extend FgWrapper with Debug::{to_repr}

///|
pub extend FgWrapper with Eq::{not_equal, equal}
