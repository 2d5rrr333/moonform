// Extreme-input robustness: out-of-range array indices on every operation,
// empty/negative edge shapes, and deeply nested structured keys. Every case
// must be a defined behavior (clamp / no-op / safe skip), never a crash.

///|
struct XItem {
  xname : String
} derive(Eq, Debug)

///|
pub extend XItem with Debug::{to_repr}

///|
pub extend XItem with Eq::{not_equal, equal}

///|
struct XForm {
  xitems : Array[XItem]
} derive(Eq, Debug)

///|
pub extend XForm with Debug::{to_repr}

///|
pub extend XForm with Eq::{not_equal, equal}

///|
fn x_items_l() -> Lens[XForm, Array[XItem]] {
  field("items", (f : XForm) => f.xitems, (_f, xs) => { xitems: xs, })
}

///|
fn x_name_at(i : Int) -> Lens[XForm, String] {
  at(x_items_l(), i).compose(
    field("name", (i : XItem) => i.xname, (_i, n) => { xname: n, }),
  )
}

///|
test "extreme: out-of-range indices on every array operation" {
  let form = FormApi::make({ xitems: [{ xname: "a", }, { xname: "b", }], })
  // insert far out of range: clamps to append
  form.insert_value(x_items_l(), 99, { xname: "c", })
  assert_eq(form.get_value(x_items_l()).length(), 3)
  assert_eq(form.get_value(x_name_at(2)), "c")
  // insert negative: clamps to front
  form.insert_value(x_items_l(), -5, { xname: "z", })
  assert_eq(form.get_value(x_name_at(0)), "z")
  assert_eq(form.get_value(x_items_l()).length(), 4)
  // remove out of range: no elements dropped, no crash
  form.remove_value(x_items_l(), 99)
  assert_eq(form.get_value(x_items_l()).length(), 4)
  form.remove_value(x_items_l(), -1)
  assert_eq(form.get_value(x_items_l()).length(), 4)
  // swap with out-of-range: value array unchanged for that position
  let before = form.get_value(x_items_l()).copy()
  form.swap_values(x_items_l(), 0, 99)
  assert_eq(form.get_value(x_items_l()), before)
  form.swap_values(x_items_l(), -3, 1)
  assert_eq(form.get_value(x_items_l()), before)
  // move out of range: no-op
  form.move_value(x_items_l(), 99, 0)
  assert_eq(form.get_value(x_items_l()), before)
  form.move_value(x_items_l(), 0, -99)
  assert_eq(form.get_value(x_items_l()), before)
  // replace out of range: no-op
  form.replace_value(x_items_l(), 42, { xname: "no", })
  assert_eq(form.get_value(x_items_l()), before)
  // clear: empties safely
  form.clear_values(x_items_l())
  assert_eq(form.get_value(x_items_l()).length(), 0)
  // ops on the now-EMPTY array: all no-ops / safe
  form.remove_value(x_items_l(), 0)
  form.insert_value(x_items_l(), 0, { xname: "n", })
  assert_eq(form.get_value(x_items_l()).length(), 1)
  form.clear_values(x_items_l())
  form.swap_values(x_items_l(), 0, 0) // empty: no-op
  form.move_value(x_items_l(), 0, 0)
  form.replace_value(x_items_l(), 0, { xname: "x", })
  assert_eq(form.get_value(x_items_l()).length(), 0)
}

///|
test "extreme: reading a stale index through the lens is safe" {
  let form = FormApi::make({ xitems: [{ xname: "a", }], })
  // a field mounted at an index that later disappears
  let f0 = form.field(x_name_at(0))
  f0.mount()
  form.remove_value(x_items_l(), 0)
  // try_get: None (slot gone), never a crash
  assert_true(x_name_at(0).try_get(form.values()) is None)
  // re-mounting a field over the stale slot is harmless
  let f0b = form.field(x_name_at(0))
  f0b.mount()
  f0b.unmount()
}

///|
struct DeepL6 {
  ln : String
} derive(Eq, Debug)

///|
pub extend DeepL6 with Debug::{to_repr}

///|
pub extend DeepL6 with Eq::{not_equal, equal}

///|
struct DeepL5 {
  d : DeepL6
} derive(Eq, Debug)

///|
pub extend DeepL5 with Debug::{to_repr}

///|
pub extend DeepL5 with Eq::{not_equal, equal}

///|
struct DeepL4 {
  detail : DeepL5
} derive(Eq, Debug)

///|
pub extend DeepL4 with Debug::{to_repr}

///|
pub extend DeepL4 with Eq::{not_equal, equal}

///|
struct DeepL3 {
  list : Array[DeepL4]
} derive(Eq, Debug)

///|
pub extend DeepL3 with Debug::{to_repr}

///|
pub extend DeepL3 with Eq::{not_equal, equal}

///|
struct DeepL2 {
  inner : DeepL3
} derive(Eq, Debug)

///|
pub extend DeepL2 with Debug::{to_repr}

///|
pub extend DeepL2 with Eq::{not_equal, equal}

///|
struct DeepL1 {
  step : DeepL2
} derive(Eq, Debug)

///|
pub extend DeepL1 with Debug::{to_repr}

///|
pub extend DeepL1 with Eq::{not_equal, equal}

///|
test "extreme: deeply nested structured keys compose and dispatch" {
  // 6-level nesting: form.step.inner.list[2].detail.name — prefix queries,
  // meta addressing, and prefix subscriptions must all handle deep keys
  // build lenses level by level
  let l1 = field("step", (v : DeepL1) => v.step, (_v, x) => { step: x, })
  let l2 = l1.compose(
    field("inner", (v : DeepL2) => v.inner, (_v, x) => { inner: x, }),
  )
  let l3 = l2.compose(
    field("list", (v : DeepL3) => v.list, (_v, x) => { list: x, }),
  )
  let l4 = at(l3, 2).compose(
    field("detail", (v : DeepL4) => v.detail, (_v, x) => { detail: x, }),
  )
  let deep = l4.compose(
    field("name", (v : DeepL5) => v.d.ln, (_v, x) => { d: { ln: x, }, }),
  )
  // the composed key renders the full path
  let expected = "step.inner.list.2.detail.name"
  assert_eq(deep.key.render(), expected)
  // a group at level 2 prefix-dispatches a write at level 6
  let l0 : DeepL6 = { ln: "0", }
  let l1v : DeepL6 = { ln: "1", }
  let l2v : DeepL6 = { ln: "2", }
  let defaults : DeepL1 = {
    step: {
      inner: {
        list: [
          { detail: { d: l0, }, },
          { detail: { d: l1v, }, },
          { detail: { d: l2v, }, },
        ],
      },
    },
  }
  let form = FormApi::make(defaults)
  let group_hits = { n: 0, }
  let inner_group = form.group(l2, on_change=_v => {
    group_hits.n = group_hits.n + 1
  })
  inner_group.mount()
  form.set_value(deep, "deep-write")
  assert_eq(group_hits.n, 1) // the level-6 write dispatched the level-2 group
  assert_eq(form.get_value(deep), "deep-write")
}

///|
struct UNested {
  u : String
} derive(Eq, Debug)

///|
pub extend UNested with Debug::{to_repr}

///|
pub extend UNested with Eq::{not_equal, equal}

///|
test "extreme: empty-string and unicode values flow through validation" {
  // a string field validated with min_length over unicode: length counts
  // codepoints (àÉ€🙂 count as 1 each)
  let u_l = field("u", (v : UNested) => v.u, (_v, x) => { u: x, })
  let form = FormApi::make({ u: "", })
  let uf = form.field(
    u_l,
    on_change_validate=validator(v => {
      if v.length() < 4 {
        ["too short"]
      } else {
        []
      }
    }),
  )
  uf.mount()
  uf.set_value("àÉ€🙂")
  assert_eq(uf.meta().errors(), []) // 4 codepoints: passes
  uf.set_value("àÉ")
  assert_eq(uf.meta().errors(), ["too short"])
}

///|
test "extreme: zero-delay and huge-delay timers on the virtual clock" {
  let vc = VirtualClock::make()
  let fired = { n: 0, }
  // zero-delay fires on schedule immediately ordering
  let _id0 = vc.schedule(0, () => fired.n = fired.n + 1)
  assert_eq(fired.n, 0) // not fired until time advances
  vc.tick(0)
  assert_eq(fired.n, 1) // zero-delay fired at t=0
  // huge delay: precise at the boundary
  let _idbig = vc.schedule(1000000, () => fired.n = fired.n + 1)
  vc.tick(999999)
  assert_eq(fired.n, 1)
  vc.tick(1)
  assert_eq(fired.n, 2)
}
