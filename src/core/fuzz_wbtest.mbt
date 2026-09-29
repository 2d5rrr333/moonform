// Randomized stress fuzz: array operations × field mount/unmount ×
// subscription churn × group error distribution, interleaved under a
// deterministic PRNG. The deterministic regression suites pin specific
// paths; this fuzz explores the CROSS-PRODUCT (the audits' standing
// blind spot — several fixed bugs depended on exact map slot layouts
// that small deterministic cases can pass over).
//
// Invariants checked after EVERY step:
//   1. values match a shadow model mirroring the documented clamp/no-op
//      semantics (catches value-layer corruption)
//   2. no meta key anywhere contains a negative index segment (catches
//      the remap-corruption class: phantom Idx(-1) keys)
//   3. group error distribution is exact: for live slots, errors exist
//      iff the element is invalid; NO errors survive on stale (>= len)
//      slots or anywhere while the group is unmounted (catches the
//      orphaned-ownership class that permanently blocked submission)
//   4. unsubscribed subscribers never fire again

///|
struct FzForm {
  fzitems : Array[String]
} derive(Eq, Debug)

///|
pub extend FzForm with Debug::{to_repr}

///|
pub extend FzForm with Eq::{not_equal, equal}

///|
fn fz_items_l() -> Lens[FzForm, Array[String]] {
  field("items", (f : FzForm) => f.fzitems, (_f, xs) => { fzitems: xs, })
}

///|
struct FzCount {
  mut hits : Int
}

///|
struct FzRand {
  mut s : Int
}

///|
fn FzRand::next(self : FzRand) -> Int {
  self.s = (self.s * 31 + 17) % 1000003
  self.s
}

///|
fn FzRand::pick(self : FzRand, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    self.next() % n
  }
}

///|
/// A random-ish index in [-1, bound] — deliberately including out-of-range
/// values so the no-op/clamp contract is exercised constantly.
fn fz_idx(r : FzRand, bound : Int) -> Int {
  r.pick(bound + 3) - 1
}

///|
fn fz_val(r : FzRand) -> String {
  let p = r.pick(3)
  if p == 0 {
    "" // invalid element: the group must distribute to it
  } else {
    "v\{r.pick(9)}"
  }
}

///|
/// Per-index required distribution straight onto the slot keys.
fn fz_validator() -> GroupValidator[Array[String], FzForm] {
  group_validator_value(xs => {
    let errs : Array[(Key, String)] = []
    for i, x in xs {
      if x == "" {
        errs.push((Key::idx(i), "required"))
      }
    }
    GroupValidationResult::fields(errs)
  })
}

///|
/// All fuzz invariants (see the file header).
fn fz_invariant(
  form : FormApi[FzForm],
  shadow : Array[String],
  group_mounted : Bool,
  ctx : String,
) -> Unit raise {
  // 1. values mirror the shadow model
  let live = form.get_value(fz_items_l())
  assert_eq(live.length(), shadow.length())
  for i in 0..<shadow.length() {
    assert_eq(live[i], shadow[i])
  }
  let items_key = fz_items_l().key
  // 2. no negative index segment in any meta key
  for k in form.meta_store().keys() {
    for seg in k.segs {
      match seg {
        Idx(i) => assert_true(i >= 0)
        Field(_) => ()
      }
    }
  }
  // 3. distribution is exact on live slots (only while the group is
  // mounted — an unmounted group distributes nothing), absent on stale
  // slots
  for i in 0..<shadow.length() {
    let k = items_key.push_idx(i)
    if shadow[i] == "" {
      if group_mounted {
        if !(form.has_field_meta(k) && form.field_meta(k).has_errors()) {
          abort(
            "fuzz \{ctx}: missing distribution at \{k.render()} (len \{shadow.length()})",
          )
        }
      }
    } else if form.field_meta(k).has_errors() {
      abort(
        "fuzz \{ctx}: unexpected error at \{k.render()} for valid value \{shadow[i]}",
      )
    }
  }
  for k in form.meta_store().keys() {
    match k.strip_prefix(items_key) {
      Some(rest) =>
        if rest.length() > 0 && form.field_meta(k).has_errors() {
          if !group_mounted {
            abort(
              "fuzz: errors survive under items while the group is unmounted: \{k.render()}",
            )
          }
          match rest.segs[0] {
            // an error on a stale slot is an orphaned distribution
            // (the permanently-blocks-submission bug class)
            Idx(i) =>
              if i >= shadow.length() {
                abort(
                  "fuzz \{ctx}: orphaned error on stale slot \{k.render()} (len \{shadow.length()})",
                )
              }
            Field(_) => ()
          }
        }
      None => ()
    }
  }
}

///|
fn fz_run(seed : Int, steps : Int) -> Unit raise {
  let r : FzRand = { s: seed, }
  let form = FormApi::make({ fzitems: ["a", "", "b"], })
  let shadow : Array[String] = ["a", "", "b"]
  let group = form.group(
    fz_items_l(),
    on_mount_validate=fz_validator(),
    on_change_validate=fz_validator(),
  )
  group.mount()
  let mut group_mounted = true
  let prefix : FzCount = { hits: 0, }
  let _psub = form.subscribe_under(fz_items_l().key, () => {
    prefix.hits = prefix.hits + 1
  })
  // a subscriber that unsubscribes immediately must never fire
  let dead : FzCount = { hits: 0, }
  let dead_id = form.subscribe(() => dead.hits = dead.hits + 1)
  form.unsubscribe(dead_id)
  // churn pair: one live subscriber alternates with one frozen (asserted
  // stable every step it stays unsubscribed)
  let mut live : (Int, FzCount)? = None
  let mut frozen : (FzCount, Int)? = None
  let mounted : Array[FieldApi[FzForm, String]] = []
  for _step in 0..<steps {
    let op = r.pick(12)
    let len = shadow.length()
    match op {
      0 => {
        let v = fz_val(r)
        form.push_value(fz_items_l(), v)
        shadow.push(v)
      }
      1 => {
        let i = fz_idx(r, len)
        let v = fz_val(r)
        form.insert_value(fz_items_l(), i, v)
        let ci = if i < 0 { 0 } else if i > len { len } else { i }
        shadow.insert(ci, v)
      }
      2 => {
        let i = fz_idx(r, len)
        form.remove_value(fz_items_l(), i)
        if i >= 0 && i < len {
          let _ = shadow.remove(i)
        }
      }
      3 => {
        let i = fz_idx(r, len)
        let j = fz_idx(r, len)
        form.swap_values(fz_items_l(), i, j)
        if i >= 0 && i < len && j >= 0 && j < len {
          let t = shadow[i]
          shadow[i] = shadow[j]
          shadow[j] = t
        }
      }
      4 => {
        let f = fz_idx(r, len)
        let t = fz_idx(r, len)
        form.move_value(fz_items_l(), f, t)
        if f >= 0 && f < len {
          // mirror the exact clamp semantics of move_value
          let to_c = if t < 0 { 0 } else if t > len - 1 { len - 1 } else { t }
          let elem = shadow[f]
          let _ = shadow.remove(f)
          let dst = if to_c >= shadow.length() { shadow.length() } else { to_c }
          shadow.insert(dst, elem)
        }
      }
      5 =>
        // clear is rare; otherwise degrade to a push
        if r.pick(8) == 0 {
          form.clear_values(fz_items_l())
          while shadow.length() > 0 {
            let _ = shadow.pop()
          }
        } else {
          let v = fz_val(r)
          form.push_value(fz_items_l(), v)
          shadow.push(v)
        }
      6 => {
        let i = fz_idx(r, len)
        let v = fz_val(r)
        if i >= 0 && i < len {
          form.set_value(at(fz_items_l(), i), v)
          shadow[i] = v
        }
      }
      7 => {
        // mounting at a stale (out-of-range) index is legal — the
        // position-survival contract. Non-negative: `at(arr, i)` addresses
        // array elements; negative indices are outside the lens contract
        // (remap-corruption guards have their own regression suite).
        let i = r.pick(len + 2)
        let f = form.field(at(fz_items_l(), i))
        f.mount()
        mounted.push(f)
      }
      8 =>
        // a field unmount clears its slot's meta wholesale — the group's
        // distribution for that slot resyncs on the next dispatch; force
        // it now so the invariant stays checkable every step
        if mounted.length() > 0 {
          let f = mounted[r.pick(mounted.length())]
          f.unmount()
          if group_mounted {
            group.validate(Change)
          }
        }
      9 =>
        if group_mounted {
          group.unmount()
          group_mounted = false
        }
      10 =>
        if !group_mounted {
          group.mount()
          group.validate(Change)
          group_mounted = true
        }
      11 => {
        let i = fz_idx(r, len)
        if i >= 0 && i < len {
          form.delete_field(fz_items_l().key.push_idx(i))
          if group_mounted {
            group.validate(Change)
          }
        }
      }
      _ => ()
    }
    // subscription churn: assert the frozen one stayed frozen, then swap
    match frozen {
      Some((fc, cnt)) => assert_eq(fc.hits, cnt)
      None => ()
    }
    match live {
      Some((id, cell)) => {
        form.unsubscribe(id)
        frozen = Some((cell, cell.hits))
        live = None
      }
      None => {
        let cell : FzCount = { hits: 0, }
        let id = form.subscribe(() => cell.hits = cell.hits + 1)
        live = Some((id, cell))
      }
    }
    fz_invariant(
      form,
      shadow,
      group_mounted,
      "seed \{seed} step \{_step} op \{op}",
    )
  }
  assert_eq(dead.hits, 0) // the dead subscriber never fired
  assert_true(prefix.hits > 0) // notifications actually flowed
}

///|
test "fuzz: array ops × mounts × subscriptions × group distribution" {
  fz_run(1, 400)
  fz_run(2, 400)
  fz_run(3, 400)
  fz_run(7, 400)
  fz_run(42, 400)
  fz_run(20260929, 400)
}
