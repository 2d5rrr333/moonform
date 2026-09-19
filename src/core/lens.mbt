///|
/// Structured field accessor — the compile-time-safe replacement for
/// dot-path strings. A lens carries the structured key it derives
/// (for internal field-state addressing) plus a getter/setter pair
/// (for typed access into the form value). Composition derives keys
/// mechanically, so refactor-renames stay consistent.
pub struct Lens[S, A] {
  key : Key
  get : (S) -> A
  set : (S, A) -> S
  /// Safe read: None when the lens addresses an array slot that no
  /// longer exists in the value (array ops can outdate mounted fields).
  try_get : (S) -> A?
}

///|
/// Lens for a named struct field.
pub fn[S, A] field(
  name : String,
  getter : (S) -> A,
  setter : (S, A) -> S,
) -> Lens[S, A] {
  {
    key: Key::field(name),
    get: getter,
    set: setter,
    try_get: s => Some(getter(s)),
  }
}

///|
/// Lens for array element `i` under an array lens. `get` requires the
/// slot to exist (value-time reads); `try_get` returns None on stale
/// indices so dispatchers can skip outdated fields safely.
pub fn[S, A] at(arr : Lens[S, Array[A]], i : Int) -> Lens[S, A] {
  {
    key: arr.key.push_idx(i),
    get: s => (arr.get)(s)[i],
    set: (s, a) => (arr.set)(s, set_idx((arr.get)(s), i, a)),
    try_get: s => {
      match (arr.try_get)(s) {
        Some(xs) =>
          match xs.get(i) {
            Some(v) => Some(v)
            None => None
          }
        None => None
      }
    },
  }
}

///|
/// The identity lens on the whole form value (key = root).
pub fn[S] identity() -> Lens[S, S] {
  { key: Key::root(), get: s => s, set: (_s, a) => a, try_get: s => Some(s), }
}

///|
pub fn[S, A] Lens::get(self : Lens[S, A], s : S) -> A {
  (self.get)(s)
}

///|
/// Safe read through the lens: None when the addressed array slot is
/// absent from the value (stale index after remove/insert).
pub fn[S, A] Lens::try_get(self : Lens[S, A], s : S) -> A? {
  (self.try_get)(s)
}

///|
pub fn[S, A] Lens::set(self : Lens[S, A], s : S, a : A) -> S {
  (self.set)(s, a)
}

///|
/// Compose a parent lens with a child lens: keys concatenate, access
/// functions compose. `parent.compose(child)` addresses `child`'s field
/// directly in `parent`'s source.
pub fn[S, M, A] Lens::compose(
  self : Lens[S, M],
  child : Lens[M, A],
) -> Lens[S, A] {
  {
    key: self.key.concat(child.key),
    get: s => (child.get)((self.get)(s)),
    set: (s, a) => (self.set)(s, (child.set)((self.get)(s), a)),
    try_get: s => {
      match (self.try_get)(s) {
        Some(m) => (child.try_get)(m)
        None => None
      }
    },
  }
}

///|
fn[A] set_idx(xs : Array[A], i : Int, a : A) -> Array[A] {
  let ys = xs.copy()
  if i >= 0 && i < ys.length() {
    ys[i] = a
  }
  ys
}
