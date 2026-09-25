// Performance bench: timed smoke over a 500-field array form — mounting,
// per-field change validation, derived-state sweeps, group checks, and
// remove-triggered meta migration. Prints per-phase wall time (js host
// clock); asserts correctness so it doubles as a scale regression test.
// Run: moon run src/examples/bench --target js

///|
struct BenchItem {
  bname : String
} derive(Eq, Debug)

///|
pub extend BenchItem with Debug::{to_repr}

///|
pub extend BenchItem with Eq::{not_equal, equal}

///|
struct BenchForm {
  bitems : Array[BenchItem]
} derive(Eq, Debug)

///|
pub extend BenchForm with Debug::{to_repr}

///|
pub extend BenchForm with Eq::{not_equal, equal}

///|
fn bench_items_l() -> @core.Lens[BenchForm, Array[BenchItem]] {
  @core.field("items", (f : BenchForm) => f.bitems, (_f, xs) => { bitems: xs, })
}

///|
fn bench_name_l() -> @core.Lens[BenchItem, String] {
  @core.field("name", (i : BenchItem) => i.bname, (_i, n) => { bname: n, })
}

///|
fn bench_name_at(i : Int) -> @core.Lens[BenchForm, String] {
  @core.at(bench_items_l(), i).compose(bench_name_l())
}

///|
extern "js" fn js_now_ms() -> Int =
  #| () => Date.now()

///|
fn main {
  let n = 500
  let xs : Array[BenchItem] = []
  for _i in 0..<n {
    xs.push({ bname: "", })
  }
  let form = @core.FormApi::make({ bitems: xs, })
  // phase 1: mount n fields with change validators
  let t0 = js_now_ms()
  for i in 0..<n {
    let f = form.field(
      bench_name_at(i),
      on_change_validate=@core.validator(v => {
        if v == "" {
          ["required"]
        } else {
          []
        }
      }),
    )
    f.mount()
  }
  let t1 = js_now_ms()
  println("bench: mount \{n} fields: \{t1 - t0}ms")
  // phase 2: n writes, each running the field's change validation
  for i in 0..<n {
    form.set_value(bench_name_at(i), "")
  }
  let t2 = js_now_ms()
  println("bench: \{n} validated writes: \{t2 - t1}ms")
  // every slot now carries an error
  let p = bench_items_l().key
  let mut errored = 0
  for k, m in form.meta_store().entries {
    if k.has_prefix(p) && m.has_errors() {
      errored = errored + 1
    }
  }
  if errored != n {
    abort("expected \{n} errored slots, got \{errored}")
  }
  // phase 3: derived-state sweeps (what bridge snapshots run per refresh)
  let rounds = 100
  for _r in 0..<rounds {
    ignore(form.is_touched())
    ignore(form.is_valid_fields())
    ignore(form.can_submit())
    ignore(form.is_dirty())
  }
  let t3 = js_now_ms()
  println("bench: \{rounds}x derived sweeps over \{n} fields: \{t3 - t2}ms")
  // phase 4: group over the array + derived checks
  let items_group = form.group(bench_items_l())
  items_group.mount()
  for _r in 0..<rounds {
    ignore(items_group.is_fields_valid())
    ignore(items_group.is_valid())
    ignore(items_group.can_submit())
  }
  let t4 = js_now_ms()
  println("bench: \{rounds}x group checks over \{n} slots: \{t4 - t3}ms")
  // phase 5: remove(0) — full meta migration across n-1 slots
  form.remove_value(bench_items_l(), 0)
  let t5 = js_now_ms()
  println("bench: remove(0) migrating \{n} slots: \{t5 - t4}ms")
  // the errors followed their elements down one index
  let mut errored2 = 0
  for k, m in form.meta_store().entries {
    if k.has_prefix(p) && m.has_errors() {
      errored2 = errored2 + 1
    }
  }
  if errored2 != n - 1 {
    abort("expected \{n - 1} errored slots after remove, got \{errored2}")
  }
  println("bench: all checks passed")
}
