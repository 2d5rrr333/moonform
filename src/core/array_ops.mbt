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
  self.meta.remap_insert(lens.key, i)
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
}

///|
/// Remove the value at `index` (upstream `removeFieldValue`): elements above
/// shift down; the vacated last slot's meta subtree is deleted. Meta
/// remaps BEFORE the value write (see insert_value) so the group change
/// re-validation sees a consistent layout.
pub fn[V, A] FormApi::remove_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index : Int,
  dont_update_meta? : Bool,
) -> Unit {
  let old = lens.get(self.values)
  let last_index = if old.length() > 0 { old.length() - 1 } else { 0 }
  self.meta.remap_remove(lens.key, index)
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
}

///|
/// Swap the values at `index1` and `index2` (upstream `swapFieldValues`).
/// Out-of-range indices leave the array unchanged for that position.
pub fn[V, A] FormApi::swap_values(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  index1 : Int,
  index2 : Int,
  dont_update_meta? : Bool,
) -> Unit {
  self.meta.remap_swap(lens.key, index1, index2)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      let in1 = index1 >= 0 && index1 < ys.length()
      let in2 = index2 >= 0 && index2 < ys.length()
      if in1 && in2 {
        let tmp = ys[index1]
        ys[index1] = ys[index2]
        ys[index2] = tmp
      }
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
}

///|
/// Move the value at `from` to `to` (upstream `moveFieldValues`): the
/// element lands at `to`; elements in between shift by one toward `from`.
pub fn[V, A] FormApi::move_value(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  from : Int,
  to : Int,
  dont_update_meta? : Bool,
) -> Unit {
  self.meta.remap_move(lens.key, from, to)
  self.meta.bump_array_version(lens.key)
  self.array_op_write(
    lens,
    xs => {
      let ys = xs.copy()
      if from >= 0 && from < ys.length() {
        let elem = ys[from]
        let _ = ys.remove(from)
        // splice semantics: out-of-range `to` appends at the end
        let dst = if to >= ys.length() {
          ys.length()
        } else if to < 0 {
          0
        } else {
          to
        }
        ys.insert(dst, elem)
      }
      ys
    },
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
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
/// no-op value-wise for non-array/empty fields, never throws.
pub fn[V, A] FormApi::clear_values(
  self : FormApi[V],
  lens : Lens[V, Array[A]],
  dont_update_meta? : Bool,
) -> Unit {
  self.array_op_write(
    lens,
    _xs => [],
    dont_update_meta=dont_update_meta.unwrap_or(false),
  )
  self.meta.bump_array_version(lens.key)
}
