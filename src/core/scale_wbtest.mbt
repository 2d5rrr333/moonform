// Scale smoke tests: correctness at size — meta migration across hundreds
// of array slots, submission over hundreds of mounted fields, prefix
// subscription fan-out under batch. These exercise the hot paths the
// derived-state checks and bridge snapshots run on every notification
// (is_touched / is_valid_fields / can_submit / has_prefix matching).

///|
struct ScaleItem {
  sname : String
} derive(Eq, Debug)

///|
pub extend ScaleItem with Debug::{to_repr}

///|
pub extend ScaleItem with Eq::{not_equal, equal}

///|
struct ScaleForm {
  sitems : Array[ScaleItem]
} derive(Eq, Debug)

///|
pub extend ScaleForm with Debug::{to_repr}

///|
pub extend ScaleForm with Eq::{not_equal, equal}

///|
fn scale_items_l() -> Lens[ScaleForm, Array[ScaleItem]] {
  field("items", (f : ScaleForm) => f.sitems, (_f, xs) => { sitems: xs, })
}

///|
fn scale_name_l() -> Lens[ScaleItem, String] {
  field("name", (i : ScaleItem) => i.sname, (_i, n) => { sname: n, })
}

///|
fn scale_name_at(i : Int) -> Lens[ScaleForm, String] {
  at(scale_items_l(), i).compose(scale_name_l())
}

///|
fn scale_defaults(n : Int) -> ScaleForm {
  let xs : Array[ScaleItem] = []
  for _i in 0..<n {
    xs.push({ sname: "", })
  }
  { sitems: xs, }
}

///|
test "scale: remove migrates errors across 200 slots" {
  let n = 200
  let form = FormApi::make(scale_defaults(n))
  for i in 0..<n {
    let f = form.field(
      scale_name_at(i),
      on_change_validate=validator(v => if v == "" { ["required"] } else { [] }),
    )
    f.mount()
  }
  // every element field carries an error
  for i in 0..<n {
    form.set_value(scale_name_at(i), "")
  }
  assert_true(form.field_meta(scale_name_at(0).key).has_errors())
  // remove slot 0: every error follows its element down one index
  form.remove_value(scale_items_l(), 0)
  assert_true(form.field_meta(scale_name_at(0).key).has_errors()) // old [1]
  // exactly n-1 errored slots remain under the array
  let p = scale_items_l().key
  let mut errored = 0
  for k, m in form.meta_store().entries {
    if k.has_prefix(p) && m.has_errors() {
      errored = errored + 1
    }
  }
  assert_eq(errored, n - 1)
}

///|
test "scale: submit validates 200 mounted fields" {
  let n = 200
  let form = FormApi::make(scale_defaults(n))
  for i in 0..<n {
    let f = form.field(
      scale_name_at(i),
      on_submit_validate=validator(v => if v == "" { ["required"] } else { [] }),
    )
    f.mount()
  }
  let submitted = { n: 0, }
  // invalid submit: every field flagged, submission blocked
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((_values, done) => {
        submitted.n = submitted.n + 1
        done(Ok)
      }),
    ),
  })
  assert_eq(submitted.n, 0)
  assert_false(form.is_submit_successful())
  // fixing every field lets the submission through
  for i in 0..<n {
    form.set_value(scale_name_at(i), "ok")
  }
  form.handle_submit(submit_options={
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((_values, done) => {
        submitted.n = submitted.n + 1
        done(Ok)
      }),
    ),
  })
  assert_eq(submitted.n, 1)
  assert_true(form.is_submit_successful())
}

///|
test "scale: prefix subscription fans out and batches" {
  let form = FormApi::make(scale_defaults(0))
  let hits = { n: 0, }
  let _id = form.subscribe_under(scale_items_l().key, () => hits.n = hits.n + 1)
  // unbatched: one notification per push
  for _i in 0..<10 {
    form.push_value(scale_items_l(), { sname: "a", })
  }
  assert_eq(hits.n, 10)
  // batched: 100 pushes coalesce to one notification
  form.batch(() => {
    for _i in 0..<100 {
      form.push_value(scale_items_l(), { sname: "b", })
    }
  })
  assert_eq(hits.n, 11)
}
