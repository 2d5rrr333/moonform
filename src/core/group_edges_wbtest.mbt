// Edge-case audit: interactions between groups and structural form changes
// (array operations, delete_field, update) — the ownership tracking of
// distributed errors must stay hygienic.

///|
struct EdgeItem {
  ename : String
} derive(Eq, Debug)

///|
pub extend EdgeItem with Debug::{to_repr}

///|
pub extend EdgeItem with Eq::{not_equal, equal}

///|
struct EdgeForm {
  eitems : Array[EdgeItem]
} derive(Eq, Debug)

///|
pub extend EdgeForm with Debug::{to_repr}

///|
pub extend EdgeForm with Eq::{not_equal, equal}

///|
fn edge_items_l() -> Lens[EdgeForm, Array[EdgeItem]] {
  field("items", (f : EdgeForm) => f.eitems, (_f, xs) => { eitems: xs, })
}

///|
fn edge_name_l() -> Lens[EdgeItem, String] {
  field("name", (i : EdgeItem) => i.ename, (_i, n) => { ename: n, })
}

///|
fn edge_name_at(i : Int) -> Lens[EdgeForm, String] {
  at(edge_items_l(), i).compose(edge_name_l())
}

///|
/// A group validator distributing per-element errors by index (the shape
/// schema_group_validator produces via JSON-Pointer paths).
fn edge_items_validator() -> GroupValidator[Array[EdgeItem], EdgeForm] {
  group_validator_value(xs => {
    let errs : Array[(Key, String)] = []
    for i, x in xs {
      if x.ename == "" {
        errs.push((Key::idx(i).push_field("name"), "required"))
      }
    }
    GroupValidationResult::fields(errs)
  })
}

///|
test "group x array ops: distributed errors migrate and re-sync" {
  let form = FormApi::make({
    eitems: [{ ename: "a", }, { ename: "", }, { ename: "", }],
  })
  let items = form.group(
    edge_items_l(),
    on_change_validate=edge_items_validator(),
  )
  let f1 = form.field(edge_name_at(1))
  let f2 = form.field(edge_name_at(2))
  items.mount()
  f1.mount()
  f2.mount()
  // a change fires the group's change validation: errors distribute at
  // items.1.name and items.2.name (elements 1 and 2 are invalid)
  form.set_value(edge_name_at(1), "")
  assert_false(items.is_fields_valid())
  // remove(0): elements shift down — errors follow to 0.name and 1.name,
  // and the group's change re-validation re-syncs against the new indices
  form.remove_value(edge_items_l(), 0)
  assert_false(items.is_fields_valid())
  assert_true(form.field_meta(edge_name_at(0).key).has_errors())
  assert_true(form.field_meta(edge_name_at(1).key).has_errors())
  assert_false(form.has_field_meta(edge_name_at(2).key)) // vacated slot gone
  // fixing the shifted elements clears the distributed errors
  form.set_value(edge_name_at(0), "ok")
  form.set_value(edge_name_at(1), "ok")
  assert_true(items.is_fields_valid())
}

///|
struct EdgeStep {
  etitle : String
} derive(Eq, Debug)

///|
pub extend EdgeStep with Debug::{to_repr}

///|
pub extend EdgeStep with Eq::{not_equal, equal}

///|
struct EdgeWizard {
  estep : EdgeStep
} derive(Eq, Debug)

///|
pub extend EdgeWizard with Debug::{to_repr}

///|
pub extend EdgeWizard with Eq::{not_equal, equal}

///|
fn edge_step_l() -> Lens[EdgeWizard, EdgeStep] {
  field("step", (w : EdgeWizard) => w.estep, (_w, s) => { estep: s, })
}

///|
fn edge_title_l() -> Lens[EdgeWizard, String] {
  edge_step_l().compose(
    field("title", (s : EdgeStep) => s.etitle, (_s, t) => { etitle: t, }),
  )
}

///|
test "group x delete_field: unmount clearing never creates meta entries" {
  let form = FormApi::make({ estep: { etitle: "", }, })
  let step = form.group(
    edge_step_l(),
    on_mount_validate=group_validator_value(_g => {
      GroupValidationResult::fields([(Key::field("title"), "required")])
    }),
  )
  step.mount()
  // the distributed error created a meta entry at step.title
  assert_true(form.has_field_meta(edge_title_l().key))
  // the field is deleted from the form (meta entry removed)
  form.delete_field(edge_title_l().key)
  assert_false(form.has_field_meta(edge_title_l().key))
  // unmounting the group must clear its distributed slots WITHOUT
  // re-creating entries for keys that no longer exist
  step.unmount()
  assert_false(form.has_field_meta(edge_title_l().key))
}

///|
test "group x stale ownership: clearing skips absent keys" {
  // a group distributes to items.0.name; delete_field removes that entry;
  // a LATER clean re-validation of the same cause must not re-create it
  let form = FormApi::make({ eitems: [{ ename: "", }, { ename: "ok", }], })
  let items = form.group(
    edge_items_l(),
    on_change_validate=edge_items_validator(),
  )
  let f0 = form.field(edge_name_at(0))
  items.mount()
  f0.mount()
  // trigger the group's change validation: element 0 is invalid, so the
  // error distributes to items.0.name
  form.set_value(edge_name_at(1), "ok")
  assert_true(form.field_meta(edge_name_at(0).key).has_errors())
  // element 0's entry (with the distributed error) is deleted wholesale
  form.delete_field(edge_name_at(0).key)
  assert_false(form.has_field_meta(edge_name_at(0).key))
  // a change elsewhere re-runs the group validator: element 0 is still
  // invalid, so the error re-distributes (single-slot replace semantics)
  form.set_value(edge_name_at(1), "still-ok")
  assert_true(form.field_meta(edge_name_at(0).key).has_errors())
  items.unmount()
}

///|
test "group x form update: registration and group state preserved" {
  let form = FormApi::make({ estep: { etitle: "", }, })
  let step = form.group(
    edge_step_l(),
    on_submit_validate=group_validator_value(g => {
      if g.etitle == "" {
        GroupValidationResult::group_error("required")
      } else {
        GroupValidationResult::valid()
      }
    }),
  )
  step.mount()
  step.handle_submit() // fails: attempts=1, group error recorded
  assert_eq(step.submission_attempts(), 1)
  assert_false(step.is_group_valid())
  // update swaps the defaults (untouched form follows); the mounted group
  // keeps its registration and its own submission/error state
  form.update(default_values={ estep: { etitle: "fresh", }, })
  assert_eq(form.get_value(edge_title_l()), "fresh")
  assert_eq(step.submission_attempts(), 1)
  assert_false(step.is_group_valid())
  // a change does NOT clear the group's Submit slot (mirrors field
  // semantics: only Mount clears on change); a re-submission does
  form.set_value(edge_title_l(), "fixed")
  assert_false(step.is_group_valid())
  step.handle_submit()
  assert_true(step.is_group_valid())
  assert_eq(step.submission_attempts(), 2)
}
