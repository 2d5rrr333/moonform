///|
/// A segment of a structured field key: either a struct field name or an
/// array index. Structured segments make sibling-prefix collisions
/// (upstream issue #2318) structurally impossible.
pub enum Seg {
  Field(String)
  Idx(Int)
} derive(Eq, Debug, Hash, Compare)

///|
/// Structured field key: ordered segments from the form root to a field.
/// Keys are the internal addressing mechanism derived from accessor
/// composition — users never write key strings by hand.
pub struct Key {
  segs : Array[Seg]
} derive(Eq, Debug, Hash, Compare)

///|
pub fn Key::root() -> Key {
  { segs: [], }
}

///|
pub fn Key::field(name : String) -> Key {
  { segs: [Field(name)], }
}

///|
pub fn Key::idx(i : Int) -> Key {
  { segs: [Idx(i)], }
}

///|
pub fn Key::from_segs(segs : Array[Seg]) -> Key {
  { segs, }
}

///|
/// Append `other` after `self`, returning a new Key (no aliasing).
pub fn Key::concat(self : Key, other : Key) -> Key {
  let segs : Array[Seg] = []
  for s in self.segs {
    segs.push(s)
  }
  for s in other.segs {
    segs.push(s)
  }
  { segs, }
}

///|
pub fn Key::push_field(self : Key, name : String) -> Key {
  self.concat(Key::field(name))
}

///|
pub fn Key::push_idx(self : Key, i : Int) -> Key {
  self.concat(Key::idx(i))
}

///|
pub fn Key::length(self : Key) -> Int {
  self.segs.length()
}

///|
/// Canonical dotted rendering, e.g. "friends.0.name" (display/diagnostic use).
pub fn Key::render(self : Key) -> String {
  let mut out = ""
  for i, seg in self.segs {
    if i > 0 {
      out = out + "."
    }
    match seg {
      Field(name) => out = out + name
      Idx(n) => out = out + n.to_string()
    }
  }
  out
}

///|
/// If `self` starts with `prefix` (whole-segment match), return the remainder.
pub fn Key::strip_prefix(self : Key, prefix : Key) -> Key? {
  let n = prefix.segs.length()
  if self.segs.length() < n {
    return None
  }
  for i in 0..<n {
    if self.segs[i] != prefix.segs[i] {
      return None
    }
  }
  Some(Key::from_segs(tail_from(self.segs, n)))
}

///|
/// Does `self` start with `prefix`? Whole-segment match, allocation-free
/// (hot path: group dispatch and prefix-subscription matching run this on
/// every value change).
pub fn Key::has_prefix(self : Key, prefix : Key) -> Bool {
  let n = prefix.segs.length()
  if self.segs.length() < n {
    return false
  }
  for i in 0..<n {
    if self.segs[i] != prefix.segs[i] {
      return false
    }
  }
  true
}

///|
fn[A] tail_from(xs : Array[A], from : Int) -> Array[A] {
  let ys : Array[A] = []
  for i in from..<xs.length() {
    ys.push(xs[i])
  }
  ys
}

// ---------------------------------------------------------------------------
// Array-operation key remapping (pure functions over structured meta stores).
//
// These implement the meta-migration semantics of upstream array operations:
// when an array mutates, the per-field state keyed under that array must
// follow the elements it belongs to.
// ---------------------------------------------------------------------------

///|
/// Apply `shift` to the first index segment appearing after `prefix`; drop
/// entries whose first index satisfies `drop`. Keys not under `prefix`
/// (whole-segment match) are kept as-is, as is the array field itself.
fn[Meta] remap_under(
  store : Map[Key, Meta],
  prefix : Key,
  shift : (Int) -> Int,
  drop : (Int) -> Bool,
) -> Map[Key, Meta] {
  let out : Map[Key, Meta] = Map([])
  for k, v in store {
    remap_entry(out, k, v, prefix, shift, drop)
  }
  out
}

///|
fn[Meta] remap_entry(
  out : Map[Key, Meta],
  k : Key,
  v : Meta,
  prefix : Key,
  shift : (Int) -> Int,
  drop : (Int) -> Bool,
) -> Unit {
  match k.strip_prefix(prefix) {
    None => out.set(k, v)
    Some(rest) =>
      if rest.segs.length() == 0 {
        // the array field itself: keep
        out.set(k, v)
      } else {
        match rest.segs[0] {
          Idx(j) =>
            if drop(j) {
              () // removed slot: drop meta
            } else {
              let nj = shift(j)
              if nj == j {
                out.set(k, v)
              } else {
                let rest2 = Key::from_segs(tail_from(rest.segs, 1))
                out.set(prefix.push_idx(nj).concat(rest2), v)
              }
            }
          _ => out.set(k, v) // non-index child directly under prefix: keep
        }
      }
  }
}

///|
/// Key remapping for `remove(i)`: slot i dropped, slots above shift down.
fn[Meta] key_remap_remove(
  store : Map[Key, Meta],
  prefix : Key,
  i : Int,
) -> Map[Key, Meta] {
  remap_under(store, prefix, j => if j > i { j - 1 } else { j }, j => j == i)
}

///|
/// Key remapping for `insert(i)`: slots at i and above shift up.
fn[Meta] key_remap_insert(
  store : Map[Key, Meta],
  prefix : Key,
  i : Int,
) -> Map[Key, Meta] {
  remap_under(store, prefix, j => if j >= i { j + 1 } else { j }, _ => false)
}

///|
/// Key remapping for `swap(i, j)`.
fn[Meta] key_remap_swap(
  store : Map[Key, Meta],
  prefix : Key,
  i : Int,
  j : Int,
) -> Map[Key, Meta] {
  remap_under(
    store,
    prefix,
    k => if k == i { j } else if k == j { i } else { k },
    _ => false,
  )
}

///|
/// Key remapping for `move(from, to)`: the element at `from` lands at `to`;
/// elements in between shift by one toward `from`.
fn[Meta] key_remap_move(
  store : Map[Key, Meta],
  prefix : Key,
  from : Int,
  to : Int,
) -> Map[Key, Meta] {
  remap_under(store, prefix, k => move_idx(k, from, to), _ => false)
}

///|
fn move_idx(idx : Int, from : Int, to : Int) -> Int {
  if from == to {
    idx
  } else if from < to {
    if idx == from {
      to
    } else if idx > from && idx <= to {
      idx - 1
    } else {
      idx
    }
  } else if idx == from {
    to
  } else if idx >= to && idx < from {
    idx + 1
  } else {
    idx
  }
}

///|
pub extend Key with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Key with Debug::{to_repr}

///|
pub extend Key with Eq::{not_equal, equal}

///|
pub extend Key with Hash::{hash, hash_combine}

///|
pub extend Seg with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Seg with Debug::{to_repr}

///|
pub extend Seg with Eq::{not_equal, equal}

///|
pub extend Seg with Hash::{hash, hash_combine}
