///|
/// Per-field state stored under the field's structured key. Values themselves
/// live in the user's form value (accessed via lens); this store holds the
/// metadata: touch/blur flags, validation lifecycle flags, and per-cause
/// errors.
pub struct FieldMetaState {
  is_touched : Bool
  is_blurred : Bool
  is_validating : Bool
  /// Stored dirty flag: set when the field is written through the form.
  /// Mounted fields derive dirtiness by value comparison instead
  /// (upstream "Prioritized Default System"); this flag covers fields
  /// written without a mounted instance.
  is_dirty : Bool
  error_map : ErrorMap
  /// Bumped whenever an array operation rekeys this field's subtree
  /// (upstream `_arrayVersion`): a cheap structural change signal for
  /// adapters that subscribe to array fields.
  array_version : Int
} derive(Eq, Debug)

///|
pub fn FieldMetaState::default_meta() -> FieldMetaState {
  {
    is_touched: false,
    is_blurred: false,
    is_validating: false,
    is_dirty: false,
    error_map: ErrorMap::empty(),
    array_version: 0,
  }
}

///|
/// Flattened errors across all recorded causes (lifecycle order).
pub fn FieldMetaState::errors(self : FieldMetaState) -> Array[String] {
  self.error_map.flatten()
}

///|
pub fn FieldMetaState::has_errors(self : FieldMetaState) -> Bool {
  self.error_map.has_errors()
}

///|
pub fn FieldMetaState::is_valid(self : FieldMetaState) -> Bool {
  !self.has_errors()
}

///|
/// Record a validation result for one cause slot (replaces the slot).
pub fn FieldMetaState::with_cause_errors(
  self : FieldMetaState,
  cause : ValidationCause,
  errors : Array[String]?,
) -> FieldMetaState {
  { ..self, error_map: self.error_map.set(cause, errors), }
}

///|
/// Key-indexed store of field metadata with prefix (subtree) queries and
/// array-operation rekeying. Structured keys make sibling-prefix collisions
/// impossible (upstream issue #2318) and give deterministic ordering.
pub struct MetaStore {
  mut entries : Map[Key, FieldMetaState]
}

///|
pub fn MetaStore::make() -> MetaStore {
  { entries: Map([]), }
}

///|
pub fn MetaStore::get(self : MetaStore, key : Key) -> FieldMetaState? {
  self.entries.get(key)
}

///|
/// Meta for `key`, defaulting (without inserting) when absent.
pub fn MetaStore::get_or_default(self : MetaStore, key : Key) -> FieldMetaState {
  match self.entries.get(key) {
    Some(m) => m
    None => FieldMetaState::default_meta()
  }
}

///|
/// Return the meta for `key`, inserting the default first if absent.
pub fn MetaStore::ensure(self : MetaStore, key : Key) -> FieldMetaState {
  match self.entries.get(key) {
    Some(m) => m
    None => {
      let m = FieldMetaState::default_meta()
      self.entries.set(key, m)
      m
    }
  }
}

///|
pub fn MetaStore::set(
  self : MetaStore,
  key : Key,
  meta : FieldMetaState,
) -> Unit {
  self.entries.set(key, meta)
}

///|
/// Update the meta for `key` functionally (default if absent; result stored).
pub fn MetaStore::update(
  self : MetaStore,
  key : Key,
  f : (FieldMetaState) -> FieldMetaState,
) -> Unit {
  let m = self.get_or_default(key)
  self.entries.set(key, f(m))
}

///|
pub fn MetaStore::remove(self : MetaStore, key : Key) -> Unit {
  let _ = self.entries.remove(key)
}

///|
pub fn MetaStore::contains(self : MetaStore, key : Key) -> Bool {
  self.entries.contains(key)
}

///|
pub fn MetaStore::length(self : MetaStore) -> Int {
  self.entries.length()
}

///|
/// All stored keys in canonical order: fewer segments first, then
/// segment-wise (Field before Idx, field names alphabetically, indices
/// numerically) — MoonBit's Array comparison is length-first.
pub fn MetaStore::keys(self : MetaStore) -> Array[Key] {
  let ks : Array[Key] = []
  for k, _v in self.entries {
    ks.push(k)
  }
  ks.sort()
  ks
}

///|
/// Keys strictly under `prefix` (the prefix itself excluded), canonical order.
pub fn MetaStore::keys_under(self : MetaStore, prefix : Key) -> Array[Key] {
  let ks : Array[Key] = []
  for k, _v in self.entries {
    match k.strip_prefix(prefix) {
      Some(rest) => if rest.length() > 0 { ks.push(k) }
      None => ()
    }
  }
  ks.sort()
  ks
}

///|
/// Remove every entry strictly under `prefix` (the prefix itself kept).
pub fn MetaStore::clear_under(self : MetaStore, prefix : Key) -> Unit {
  for k in self.keys_under(prefix) {
    self.entries.remove(k)
  }
}

///|
/// Bump `array_version` on the array field's own meta (structural signal
/// that the array mutated in a way length cannot express, e.g. swap/move).
pub fn MetaStore::bump_array_version(self : MetaStore, key : Key) -> Unit {
  self.update(key, m => { ..m, array_version: m.array_version + 1, })
}

// -- array-operation rekeying ------------------------------------------------

///|
/// Rekey for `remove(i)`: drop slot i, shift above-indices down.
pub fn MetaStore::remap_remove(self : MetaStore, prefix : Key, i : Int) -> Unit {
  self.entries = key_remap_remove(self.entries, prefix, i)
}

///|
/// Rekey for `insert(i)`: shift at-and-above-indices up. The new slot at i
/// starts without meta (upstream clears inserted slots to default meta).
pub fn MetaStore::remap_insert(self : MetaStore, prefix : Key, i : Int) -> Unit {
  self.entries = key_remap_insert(self.entries, prefix, i)
  self.clear_under(prefix.push_idx(i))
}

///|
/// Rekey for `swap(i, j)`.
pub fn MetaStore::remap_swap(
  self : MetaStore,
  prefix : Key,
  i : Int,
  j : Int,
) -> Unit {
  self.entries = key_remap_swap(self.entries, prefix, i, j)
}

///|
/// Rekey for `move(from, to)`.
pub fn MetaStore::remap_move(
  self : MetaStore,
  prefix : Key,
  from : Int,
  to : Int,
) -> Unit {
  self.entries = key_remap_move(self.entries, prefix, from, to)
}

///|
pub extend FieldMetaState with Debug::{to_repr}

///|
pub extend FieldMetaState with Eq::{not_equal, equal}
