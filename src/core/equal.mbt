/// Deep-equality protocol for form values.
///
/// MoonBit's `derive(Eq)` performs deep structural comparison (including
/// array fields), which replaces TanStack Form's runtime deep-equal on plain
/// objects. Form value types SHOULD `derive(Eq)` so the core can derive
/// `is_dirty` states; this is the documented contract of the value-semantics
/// deviation recorded in the upstream-parity spec.

///|
/// Is the field addressed by `lens` dirty, i.e. does its current value
/// differ (deeply) from its value in `defaults`?
pub fn[S, A : Eq] field_is_dirty(
  lens : Lens[S, A],
  current : S,
  defaults : S,
) -> Bool {
  lens.get(current) != lens.get(defaults)
}

///|
/// Are two whole form values deeply equal?
pub fn[V : Eq] values_equal(current : V, defaults : V) -> Bool {
  current == defaults
}
