// Regression audit: array operations and stale slots.
//
// B1: groups mounted on array elements must never crash (lens.get on an
//     out-of-range index aborts) and their registrations must go away with
//     the vacated slot.
// B2/B3: distributed-error ownership must migrate with the meta remap, and
//     a clean re-validation must never wipe content another writer owns.
// B4: out-of-range remove/swap/move indices must be full no-ops (values
//     AND meta) — remapping with a bad index corrupted the meta layout.

///|
struct AgItem {
  agname : String
} derive(Eq, Debug)

///|
pub extend AgItem with Debug::{to_repr}

///|
pub extend AgItem with Eq::{not_equal, equal}

///|
struct AgForm {
  agitems : Array[AgItem]
} derive(Eq, Debug)

///|
pub extend AgForm with Debug::{to_repr}

///|
pub extend AgForm with Eq::{not_equal, equal}

///|
fn ag_items_l() -> Lens[AgForm, Array[AgItem]] {
  field("items", (f : AgForm) => f.agitems, (_f, xs) => { agitems: xs, })
}

///|
fn ag_name_l() -> Lens[AgItem, String] {
  field("name", (i : AgItem) => i.agname, (_i, n) => { agname: n, })
}

///|
fn ag_name_at(i : Int) -> Lens[AgForm, String] {
  at(ag_items_l(), i).compose(ag_name_l())
}

///|
/// A group validator distributing per-element errors by index.
fn ag_items_validator() -> GroupValidator[Array[AgItem], AgForm] {
  group_validator_value(xs => {
    let errs : Array[(Key, String)] = []
    for i, x in xs {
      if x.agname == "" {
        errs.push((Key::idx(i).push_field("name"), "required"))
      }
    }
    GroupValidationResult::fields(errs)
  })
}

// ---------------------------------------------------------------------------
// B4: out-of-range indices are full no-ops
// ---------------------------------------------------------------------------

///|
test "array ops: out-of-range remove is a full no-op (values AND meta)" {
  let form = FormApi::make({ agitems: [{ agname: "a", }, { agname: "b", }], })
  let f0 = form.field(ag_name_at(0))
  let f1 = form.field(ag_name_at(1))
  f0.mount()
  f1.mount()
  form.set_value(ag_name_at(0), "changed0")
  form.set_value(ag_name_at(1), "changed1")
  assert_true(form.has_field_meta(ag_name_at(0).key))
  assert_true(form.has_field_meta(ag_name_at(1).key))
  // remove(-1): values unchanged, meta NOT shifted onto phantom Idx(-1)
  form.remove_value(ag_items_l(), -1)
  assert_eq(form.get_value(ag_items_l()).length(), 2)
  assert_true(form.has_field_meta(ag_name_at(0).key))
  assert_true(form.field_meta(ag_name_at(0).key).is_touched)
  // remove(99): values unchanged, the last slot's meta NOT deleted
  form.remove_value(ag_items_l(), 99)
  assert_eq(form.get_value(ag_items_l()).length(), 2)
  assert_true(form.has_field_meta(ag_name_at(1).key))
  assert_true(form.field_meta(ag_name_at(1).key).is_touched)
}

///|
test "array ops: out-of-range swap is a full no-op (values AND meta)" {
  let form = FormApi::make({ agitems: [{ agname: "a", }, { agname: "b", }], })
  let f0 = form.field(ag_name_at(0))
  f0.mount()
  form.set_value(ag_name_at(0), "changed0")
  // swap(0, 99): the value layer no-ops; the meta remap must too (the old
  // remap exiled items.0's subtree to the phantom key items.99)
  form.swap_values(ag_items_l(), 0, 99)
  assert_eq(form.get_value(ag_name_at(0)), "changed0")
  assert_eq(form.get_value(ag_name_at(1)), "b")
  assert_true(form.has_field_meta(ag_name_at(0).key))
  assert_false(
    form.has_field_meta(ag_items_l().key.push_idx(99).push_field("name")),
  )
  // swap(-1, 0) mirrors it
  form.swap_values(ag_items_l(), -1, 0)
  assert_eq(form.get_value(ag_name_at(0)), "changed0")
  assert_true(form.has_field_meta(ag_name_at(0).key))
}

///|
test "array ops: out-of-range move is a full no-op; clamped to matches values" {
  let form = FormApi::make({
    agitems: [{ agname: "a", }, { agname: "b", }, { agname: "c", }],
  })
  let f0 = form.field(ag_name_at(0))
  let f2 = form.field(ag_name_at(2))
  f0.mount()
  f2.mount()
  form.set_value(ag_name_at(0), "changed0")
  form.set_value(ag_name_at(2), "changed2")
  // move(99, 0): the value layer no-ops; the old remap shifted ALL slots'
  // meta up by one against unchanged values
  form.move_value(ag_items_l(), 99, 0)
  assert_eq(form.get_value(ag_name_at(0)), "changed0")
  assert_eq(form.get_value(ag_name_at(2)), "changed2")
  assert_true(form.has_field_meta(ag_name_at(0).key))
  assert_true(form.has_field_meta(ag_name_at(2).key))
  assert_false(form.has_field_meta(ag_items_l().key.push_idx(3)))
  // move(0, 99): to clamps to the end — meta must land where the value did
  form.move_value(ag_items_l(), 0, 99)
  assert_eq(form.get_value(ag_name_at(2)), "changed0")
  assert_true(
    form.field_meta(ag_items_l().key.push_idx(2).push_field("name")).is_touched,
  )
}

// ---------------------------------------------------------------------------
// B2/B3: ownership migration × distributed errors
// ---------------------------------------------------------------------------

///|
test "group: distributed submit errors migrate with remove and stay clearable" {
  let form = FormApi::make({ agitems: [{ agname: "a", }, { agname: "", }], })
  let items = form.group(ag_items_l(), on_submit_validate=ag_items_validator())
  items.mount()
  items.handle_submit() // distributes "required" to items.1.name
  assert_true(form.field_meta(ag_name_at(1).key).has_errors())
  // remove(0): the errored element shifts to index 0; ownership must follow
  form.remove_value(ag_items_l(), 0)
  assert_true(form.field_meta(ag_name_at(0).key).has_errors())
  // fix the shifted element and re-submit: the migrated error must clear
  // (stale ownership left it orphaned forever — the group could never
  // submit again)
  form.set_value(ag_name_at(0), "ok")
  items.handle_submit()
  assert_false(form.field_meta(ag_name_at(0).key).has_errors())
  assert_true(items.is_fields_valid())
  assert_true(items.is_group_valid())
}

///|
test "group: distributed change errors migrate with insert/swap/move" {
  let form = FormApi::make({ agitems: [{ agname: "", }, { agname: "b", }], })
  let items = form.group(ag_items_l(), on_change_validate=ag_items_validator())
  items.mount()
  // fire the change validation: element 0's error distributes to items.0
  form.set_value(ag_name_at(1), "b")
  assert_true(form.field_meta(ag_name_at(0).key).has_errors())
  // insert(0, ok): the errored element shifts to index 1; ownership follows
  form.insert_value(ag_items_l(), 0, { agname: "ok", })
  assert_true(form.field_meta(ag_name_at(1).key).has_errors())
  // fixing the shifted element and re-validating clears the migrated error
  form.set_value(ag_name_at(1), "ok")
  assert_false(form.field_meta(ag_name_at(1).key).has_errors())
  assert_true(items.is_fields_valid())
}

///|
test "group: owned clear never wipes another writer's error after remap" {
  let form = FormApi::make({ agitems: [{ agname: "", }, { agname: "kept", }], })
  let items = form.group(
    ag_items_l(),
    on_change_validate=group_validator_value(xs => {
      if xs[0].agname == "" {
        GroupValidationResult::fields([
          (Key::idx(0).push_field("name"), "required"),
        ])
      } else {
        GroupValidationResult::valid()
      }
    }),
  )
  let f1 = form.field(
    ag_name_at(1),
    on_change_validate=validator(v => if v == "kept" { ["own"] } else { [] }),
  )
  items.mount()
  f1.mount()
  // distribute: the group's error lands at items.0.name; the field's own
  // Change error lands at items.1.name
  form.set_value(ag_name_at(1), "kept")
  assert_true(form.field_meta(ag_name_at(0).key).has_errors())
  assert_true(form.field_meta(ag_name_at(1).key).has_errors())
  // remove(0): the field's own meta (with its error) re-seats at index 0
  // and the group re-validates clean — the clear must NOT wipe the field's
  // own error (CAS: another writer's content wins)
  form.remove_value(ag_items_l(), 0)
  let m = form.field_meta(ag_name_at(0).key)
  assert_true(m.has_errors())
  assert_eq(m.error_map.get(Change), Some(["own"]))
}

// ---------------------------------------------------------------------------
// B1: groups on array elements — stale slots never crash
// ---------------------------------------------------------------------------

///|
struct AgStrings {
  agnames : Array[String]
} derive(Eq, Debug)

///|
pub extend AgStrings with Debug::{to_repr}

///|
pub extend AgStrings with Eq::{not_equal, equal}

///|
fn ag_names_l() -> Lens[AgStrings, Array[String]] {
  field("names", (f : AgStrings) => f.agnames, (_f, xs) => { agnames: xs, })
}

///|
test "group on array element: stale after removal never aborts" {
  let form = FormApi::make({ agnames: ["a", "b", "c"], })
  let g2 = form.group(
    at(ag_names_l(), 2),
    on_change_validate=group_validator_value(s => {
      if s == "" {
        GroupValidationResult::group_error("empty")
      } else {
        GroupValidationResult::valid()
      }
    }),
  )
  g2.mount()
  // remove(0) shrinks the array to length 2: slot 2 no longer exists
  form.remove_value(ag_names_l(), 0)
  // a write addressed at the (now out-of-range) slot used to reach the
  // group dispatch and abort inside lens.get — the dispatch must skip the
  // stale slot through try_get instead
  form.set_value(at(ag_names_l(), 2), "x")
  assert_eq(form.get_value(ag_names_l()).length(), 2)
  // the stale handle's own methods must not abort either, and must not
  // record phantom group errors
  g2.validate(Change)
  g2.handle_submit()
  assert_eq(g2.error_for_cause(Change), None)
  assert_eq(g2.error_for_cause(Submit), None)
}

///|
test "group on array element: empty array after clear never aborts" {
  let form = FormApi::make({ agnames: ["a", "b"], })
  let g0 = form.group(
    at(ag_names_l(), 0),
    on_change_validate=group_validator_value(s => {
      if s == "" {
        GroupValidationResult::group_error("empty")
      } else {
        GroupValidationResult::valid()
      }
    }),
  )
  g0.mount()
  form.clear_values(ag_names_l())
  assert_eq(form.get_value(ag_names_l()).length(), 0)
  // writes into the emptied array's slots dispatch the group against an
  // out-of-range index — try_get skips, no abort, no phantom errors
  form.set_value(at(ag_names_l(), 0), "x")
  form.set_value(at(ag_names_l(), 1), "y")
  assert_eq(g0.error_for_cause(Change), None)
}
