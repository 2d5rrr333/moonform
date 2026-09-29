// Array field operations (upstream pushFieldValue / insertFieldValue /
// removeFieldValue / swapFieldValues / moveFieldValues / replaceFieldValue /
// clearFieldValues), ported to lens-addressed arrays:
//
// - values mutate through the array lens (value semantics, new array each op)
// - meta rekeys through the MetaStore's structured remapping
// - each op bumps the array field's `array_version` (structural change
//   signal for adapters — length alone cannot express swap/move)
// - validation hooks fire once the validation phase is wired (deviation:
//   synchronous orchestration now; async revalidation of shifted fields is
//   driven by the caller via Clock in the validation phase)

///|
fn[V, A] FormApi::array_op_write(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  f : (Array[A]) -> Array[A],
  dont_update_meta? : Bool,
) -> Unit {
  let old = lens.get(self.values)
  let next = f(old)
  self.set_value(
    lens,
    next,
    dont_update_meta=dont_update_meta.unwrap_or(false),
    dont_run_listeners=false,
    dont_validate=true, // array ops orchestrate validation themselves
  )
}

///|
/// Push a value onto the end of an array field (upstream `pushFieldValue`).
pub fn[V, A] FormApi::push_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  value : A,
  dont_update_meta? : Bool,
) -> Unit {
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      ys.push(value)
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  self.meta.bump_array_version(lens.key)
}

///|
/// Insert a value at `index` (upstream `insertFieldValue`): elements at
/// `index` and above shift up; an out-of-range index appends to the end.
/// The new slot starts without meta (upstream clears inserted slots).
/// Meta remaps BEFORE the value write so the group change re-validation
/// (dispatched by the write) sees a meta layout consistent with the new
/// values — remapping after would scramble the freshly distributed errors.
pub fn[V, A] FormApi::insert_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index : Int,
  value : A,
  dont_update_meta? : Bool,
) -> Unit {
  let len = lens.get(self.values).length()
  let i = if index < 0 { 0 } else if index > len { len } else { index }
  self.remap_insert(lens.key, i)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys : Array[A] = []
      for j, x in xs {
        if j == i {
          ys.push(value)
        }
        ys.push(x)
      }
      if i >= xs.length() {
        ys.push(value) // append at (or beyond) the end
      }
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  // slots at and above i shifted: element-addressed subscribers refresh
  self.notify_structural_change(lens.key)
}

// -- array-op remap wrappers ---------------------------------------------------

///|
/// Notify every subscriber of a structural change under `prefix`: all
/// per-slot keys are notified (Meta) in one batch — element-addressed
/// subscribers (field/group bridges) refresh their snapshots even though
/// their own key was never written (swap/move/remove shifted a DIFFERENT
/// slot's data onto their position). Batched so each subscriber fires at
/// most once per operation.
fn[V] FormApi::notify_structural_change(
  self : FormApi[V],
  prefix : Key,
) -> Unit {
  let ks = self.meta.keys_under(prefix)
  if ks.length() == 0 {
    return
  }
  self.subs.batch(() => {
    for k in ks {
      self.subs.notify(k, Meta)
    }
  })
}

///|
/// Meta remap for remove(i) + group ownership migration (distributed-error
/// records follow the elements their errors moved to — see
/// `FormApi::remap_group_owned`).
fn[V] FormApi::remap_remove(self : FormApi[V], prefix : Key, i : Int) -> Unit {
  self.meta.remap_remove(prefix, i)
  self.remap_group_owned(prefix, j => if j > i { j - 1 } else { j }, j => j == i)
}

///|
/// Meta remap for insert(i) + group ownership migration.
fn[V] FormApi::remap_insert(self : FormApi[V], prefix : Key, i : Int) -> Unit {
  self.meta.remap_insert(prefix, i)
  self.remap_group_owned(prefix, j => if j >= i { j + 1 } else { j }, _ => false)
}

///|
/// Meta remap for swap(i, j) + group ownership migration.
fn[V] FormApi::remap_swap(
  self : FormApi[V],
  prefix : Key,
  i : Int,
  j : Int,
) -> Unit {
  self.meta.remap_swap(prefix, i, j)
  self.remap_group_owned(
    prefix,
    k => if k == i { j } else if k == j { i } else { k },
    _ => false,
  )
}

///|
/// Meta remap for move(from, to) + group ownership migration.
fn[V] FormApi::remap_move(
  self : FormApi[V],
  prefix : Key,
  from : Int,
  to : Int,
) -> Unit {
  self.meta.remap_move(prefix, from, to)
  self.remap_group_owned(prefix, k => move_idx(k, from, to), _ => false)
}

///|
/// Remove the value at `index` (upstream `removeFieldValue`): elements above
/// shift down; the vacated last slot's meta subtree is deleted. Meta
/// remaps BEFORE the value write (see insert_value) so the group change
/// re-validation sees a consistent layout. An out-of-range index is a FULL
/// no-op (values and meta alike — remapping with a bad index would corrupt
/// the meta layout against unchanged values).
pub fn[V, A] FormApi::remove_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index : Int,
  dont_update_meta? : Bool,
) -> Unit {
  let old = lens.get(self.values)
  if index < 0 || index >= old.length() {
    return // out-of-range: no-op (value layer AND meta layer)
  }
  let last_index = old.length() - 1
  self.remap_remove(lens.key, index)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys : Array[A] = []
      for j, x in xs {
        if j != index {
          ys.push(x)
        }
      }
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  // delete the vacated last slot (upstream deletes `${field}[${lastIndex}]`)
  self.delete_field(lens.key.push_idx(last_index))
  // every surviving slot's data shifted: element-addressed subscribers
  // refresh even though their key was never written
  self.notify_structural_change(lens.key)
}

///|
/// Swap the values at `index1` and `index2` (upstream `swapFieldValues`).
/// An out-of-range index is a FULL no-op (values and meta alike — the meta
/// remap would exile the slot's subtree to a phantom key while the value
/// layer stays unchanged).
pub fn[V, A] FormApi::swap_values(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index1 : Int,
  index2 : Int,
  dont_update_meta? : Bool,
) -> Unit {
  let len = lens.get(self.values).length()
  if index1 < 0 || index1 >= len || index2 < 0 || index2 >= len {
    return // out-of-range: no-op (value layer AND meta layer)
  }
  self.remap_swap(lens.key, index1, index2)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      let tmp = ys[index1]
      ys[index1] = ys[index2]
      ys[index2] = tmp
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  // both swapped slots' data moved: element-addressed subscribers refresh
  self.notify_structural_change(lens.key)
}

///|
/// Move the value at `from` to `to` (upstream `moveFieldValues`): the
/// element lands at `to`; elements in between shift by one toward `from`.
/// An out-of-range `from` is a FULL no-op; `to` is clamped to the array
/// bounds so the meta remap matches where the element actually lands.
pub fn[V, A] FormApi::move_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  from : Int,
  to : Int,
  dont_update_meta? : Bool,
) -> Unit {
  let len = lens.get(self.values).length()
  if from < 0 || from >= len {
    return // out-of-range source: no-op (value layer AND meta layer)
  }
  let to_c = if to < 0 { 0 } else if to > len - 1 { len - 1 } else { to }
  self.remap_move(lens.key, from, to_c)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      let elem = ys[from]
      let _ = ys.remove(from)
      // splice semantics: to_c == len-1 lands at the end after the removal
      let dst = if to_c >= ys.length() { ys.length() } else { to_c }
      ys.insert(dst, elem)
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  // every slot between from and to shifted: element-addressed subscribers
  // refresh
  self.notify_structural_change(lens.key)
}

///|
/// Replace the value at `index` (upstream `replaceFieldValue`): a
/// non-existent index leaves the array unchanged (no-op).
pub fn[V, A] FormApi::replace_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index : Int,
  value : A,
  dont_update_meta? : Bool,
) -> Unit {
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      if index >= 0 && index < ys.length() {
        ys[index] = value
      }
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  self.meta.bump_array_version(lens.key)
}

///|
/// Clear all values of an array field (upstream `clearFieldValues`); a
/// no-op value-wise for non-array/empty fields, never throws. Every old
/// slot is vacated — its meta and registration go away with the element
/// (mirroring remove_value's vacated-slot deletion; clear is remove for
/// every position). Without the per-slot cleanup, Mount-cause distributed
/// errors on the stale slots survive as orphans (a Change re-validation
/// only clears its own cause's records) and block the group forever.
pub fn[V, A] FormApi::clear_values(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  dont_update_meta? : Bool,
) -> Unit {
  let len = lens.get(self.values).length()
  self.array_op_write(
    lens,
    _xs => [],
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  for i in 0..<len {
    // delete_field notifies the removed subtree — element-addressed
    // subscribers see the clear
    self.delete_field(lens.key.push_idx(i))
  }
  self.meta.bump_array_version(lens.key)
}
