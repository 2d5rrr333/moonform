// Field mount/unmount semantics (translated from FieldApi.spec unmount
// tests; the error-clearing behavior uses manually seeded meta errors until
// the validation phase provides real ones).

// upstream: "should preserve value on unmount"

///|
test "unmount: value is preserved" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  field.set_value("changed")
  field.unmount()
  assert_eq(form.get_value(name_l()), "changed")
}

// upstream: "should clear meta on unmount while preserving value" —
// errors are cleared, interaction flags kept, remount sees value + touched

///|
test "unmount: errors clear, interaction flags and value persist" {
  let form = FormApi::make({ name: "a", surname: "abc", age: 0, })
  let last_l = surname_l()
  let field = form.field(last_l)
  field.mount()
  // simulate an onSubmit validation error + touched state
  form
  .meta_store()
  .update(last_l.key, m => {
    ..m,
    is_touched: true,
    error_map: m.error_map.set(
      Submit,
      Some(["last name must be at least 5 chars"]),
    ),
  })
  assert_true(form.field_meta(last_l.key).has_errors())
  field.unmount()
  let m = form.field_meta(last_l.key)
  assert_false(m.has_errors()) // errors cleared
  assert_true(m.is_touched) // interaction flag kept
  assert_eq(form.get_value(last_l), "abc") // value kept
  // remount: value and touched flag survive, errors stay clear
  let remounted = form.field(last_l)
  remounted.mount()
  let m2 = remounted.meta()
  assert_eq(m2.errors(), [])
  assert_true(m2.is_touched)
  assert_eq(remounted.value(), "abc")
}

// upstream: "should preserve field-level defaultValue changes across
// unmount remount cleanup"

///|
test "unmount: user-entered value survives remount despite field default" {
  let form = FormApi::make({ name: "", surname: "", age: 0, })
  let field = form.field(name_l(), default="initial")
  field.mount()
  field.set_value("changed")
  field.unmount()
  let remounted = form.field(name_l(), default="initial")
  remounted.mount()
  assert_eq(remounted.value(), "changed")
}

// upstream: "should not clear newer instance state when older instance
// unmounts"

///|
test "unmount: stale instance unmount is a no-op for the newer owner" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let older = form.field(name_l())
  older.mount()
  let newer = form.field(name_l())
  newer.mount() // takes over the registration
  newer.set_value("from-newer")
  older.unmount() // stale: must not touch registration or meta
  assert_eq(form.get_value(name_l()), "from-newer")
  assert_true(form.has_field_meta(name_l().key))
  // newer instance is still fully functional
  newer.set_value("again")
  assert_eq(form.get_value(name_l()), "again")
}

// upstream: "should run form listener onFieldUnmount"

///|
test "unmount: form-level on_field_unmount listener runs" {
  let cell = StrCell::make()
  let form = FormApi::make({ name: "test", surname: "", age: 0, }, on_field_unmount=key => {
    cell.v = Some(key.render())
  })
  let field = form.field(name_l())
  field.mount()
  assert_eq(cell.v, None)
  field.unmount()
  assert_eq(cell.v, Some("name"))
}

// upstream: "should ignore cleanup when fieldInfo was deleted before
// unmount" + "should not run onUnmount listener if fieldInfo was already
// deleted"

///|
test "unmount: after delete_field, unmount is silent" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let field = form.field(name_l(), on_unmount=() => count.n = count.n + 1)
  field.mount()
  form.delete_field(name_l().key)
  field.unmount() // must not throw, must not run the listener
  assert_eq(count.n, 0)
}

// delete_field removes the field's meta subtree but keeps values

///|
test "delete_field: removes meta subtree, keeps values" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let field = form.field(name_l())
  field.mount()
  form.set_value(name_l(), "other")
  form.delete_field(name_l().key)
  assert_false(form.has_field_meta(name_l().key))
  assert_eq(form.get_value(name_l()), "other") // values kept (typed model)
}

// meta entries written before a field mounts are not lost on mount
// (upstream: validation errors for not-yet-mounted fields)

///|
test "mount: pre-existing meta entry survives mount" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  // a form-level writer stores an error for the not-yet-mounted field
  form
  .meta_store()
  .update(name_l().key, m => {
    ..m,
    error_map: m.error_map.set(Change, Some(["early error"])),
  })
  let field = form.field(name_l())
  field.mount()
  assert_true(field.meta().has_errors())
  assert_eq(field.meta().errors(), ["early error"])
}
