// Array field value operations, translated from form-core@1.33.5
// FormApi.spec.ts array block (value-level assertions).

///|
struct Arr {
  names : Array[String]
} derive(Eq, Debug)

///|
fn arr_defaults() -> Arr {
  { names: ["test"], }
}

///|
fn names_l() -> Lens[Arr, Array[String]] {
  field("names", a => a.names, (_a, xs) => { names: xs, })
}

///|
fn names_of(form : FormApi[Arr]) -> Array[String] {
  form.get_value(names_l())
}

// upstream: "should push an array field's value"

///|
test "array ops: push appends to the end" {
  let form = FormApi::make(arr_defaults())
  form.push_value(names_l(), "other")
  assert_eq(names_of(form), ["test", "other"])
}

// upstream: "should insert an array field's value as first element"

///|
test "array ops: insert as first element" {
  let form = FormApi::make({ names: ["test"], })
  form.insert_value(names_l(), 0, "other")
  assert_eq(names_of(form), ["other", "test"])
}

// upstream: "should insert an array field's value at the end if the index
// is higher than the length"

///|
test "array ops: out-of-range insert appends to the end" {
  let form = FormApi::make({ names: ["test"], })
  form.insert_value(names_l(), 10, "other")
  assert_eq(names_of(form), ["test", "other"])
}

// upstream: "should insert an array field's value"

///|
test "array ops: insert in the middle" {
  let form = FormApi::make({ names: ["one", "two"], })
  form.insert_value(names_l(), 1, "middle")
  assert_eq(names_of(form), ["one", "middle", "two"])
}

// upstream: "should remove an array field's value"

///|
test "array ops: remove shifts following elements down" {
  let form = FormApi::make({ names: ["one", "two", "three"], })
  form.remove_value(names_l(), 1)
  assert_eq(names_of(form), ["one", "three"])
}

// upstream: "should swap an array field's value"

///|
test "array ops: swap exchanges two elements" {
  let form = FormApi::make({ names: ["one", "two", "three"], })
  form.swap_values(names_l(), 0, 2)
  assert_eq(names_of(form), ["three", "two", "one"])
}

// upstream: "should move an array field's value"

///|
test "array ops: move relocates an element" {
  let form = FormApi::make({ names: ["one", "two", "three"], })
  form.move_value(names_l(), 0, 2)
  assert_eq(names_of(form), ["two", "three", "one"])
  form.move_value(names_l(), 2, 0)
  assert_eq(names_of(form), ["one", "two", "three"])
}

// upstream: "should replace an array field's value"

///|
test "array ops: replace overwrites an element" {
  let form = FormApi::make({ names: ["one", "two"], })
  form.replace_value(names_l(), 1, "changed")
  assert_eq(names_of(form), ["one", "changed"])
}

// upstream: "should do nothing when replacing an array field's value with
// an index that doesn't exist"

///|
test "array ops: replace with nonexistent index is a no-op" {
  let form = FormApi::make({ names: ["one", "two"], })
  form.replace_value(names_l(), 5, "changed")
  assert_eq(names_of(form), ["one", "two"])
}

// upstream: "should run the onChange listener when the field array is
// changed" (value assertions; full listener choreography uses validation)

///|
test "array ops: onChange listener fires with the new array (value part)" {
  let form = FormApi::make({ names: ["one", "two"], })
  let seen : Array[Array[String]] = []
  let field = form.field(names_l(), on_change=xs => seen.push(xs))
  field.mount()
  form.remove_value(names_l(), 1)
  form.replace_value(names_l(), 0, "start")
  form.push_value(names_l(), "end")
  form.insert_value(names_l(), 1, "middle")
  form.swap_values(names_l(), 0, 2)
  form.move_value(names_l(), 0, 1)
  form.clear_values(names_l())
  assert_eq(seen.length(), 7) // every operation notifies once
  assert_eq(seen[0], ["one"])
  assert_eq(seen[1], ["start"])
  assert_eq(seen[2], ["start", "end"])
  assert_eq(seen[3], ["start", "middle", "end"])
  assert_eq(seen[4], ["end", "middle", "start"])
  assert_eq(seen[5], ["middle", "end", "start"])
  assert_eq(seen[6], [])
}

// upstream: "should not break when clearValues is called on a non-array
// field" — in the typed model clear_values requires an array lens, so the
// non-array case cannot be expressed; clearing an empty array must be safe.

///|
test "array ops: clear on empty array is safe" {
  let form = FormApi::make({ names: [], })
  form.clear_values(names_l())
  assert_eq(names_of(form), [])
}

///|
test "array ops: array_version bumps on each operation" {
  let form = FormApi::make(arr_defaults())
  form.push_value(names_l(), "x")
  assert_eq(form.field_meta(names_l().key).array_version, 1)
  form.swap_values(names_l(), 0, 0)
  assert_eq(form.field_meta(names_l().key).array_version, 2)
  form.move_value(names_l(), 0, 0)
  assert_eq(form.field_meta(names_l().key).array_version, 3)
}

///|
test "array ops: remove deletes the vacated last slot's meta" {
  let form = FormApi::make({ names: ["a", "b", "c"], })
  // meta for names.1 exists (e.g. from a mounted subfield)
  form
  .meta_store()
  .update(names_l().key.push_idx(1), m => { ..m, is_touched: true, })
  form.remove_value(names_l(), 0)
  // slot 1 meta moved to 0; the vacated slot 2 (lastIndex) subtree is gone
  assert_true(form.field_meta(names_l().key.push_idx(0)).is_touched)
  assert_false(form.has_field_meta(names_l().key.push_idx(1)))
}

///|
test "array ops: operations are value-semantic on the original defaults" {
  let d = arr_defaults()
  let form = FormApi::make(d)
  form.push_value(names_l(), "other")
  form.remove_value(names_l(), 0)
  assert_eq(d, { names: ["test"], }) // original untouched
}

///|
pub extend Arr with Debug::{to_repr}

///|
pub extend Arr with Eq::{not_equal, equal}
