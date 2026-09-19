// moonform/rules: built-in lightweight validation rules.
// All rules implement the core Validator protocol; zero third-party
// dependencies; js/wasm/native portable.

///|
/// "required" — the value must be non-empty: non-empty string, non-empty
/// array, or non-None option. Error message defaults to "Required".
pub fn[V] required(message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Required")
  @core.validator(v => if v.length() == 0 { [msg] } else { [] })
}

///|
/// "required" for array values: the array must contain at least one item.
pub fn[V] required_array(
  message? : String,
) -> @core.Validator[Array[String], V] {
  let msg = message.unwrap_or("Required")
  @core.validator(xs => if xs.length() == 0 { [msg] } else { [] })
}

///|
/// Minimum string length (inclusive).
pub fn[V] min_length(n : Int, message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Must be at least \{n} characters")
  @core.validator(v => if v.length() < n { [msg] } else { [] })
}

///|
/// Maximum string length (inclusive).
pub fn[V] max_length(n : Int, message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Must be at most \{n} characters")
  @core.validator(v => if v.length() > n { [msg] } else { [] })
}

///|
/// Minimum numeric value (inclusive).
pub fn[V] min_value(
  n : Double,
  message? : String,
) -> @core.Validator[Double, V] {
  let msg = message.unwrap_or("Must be at least \{n}")
  @core.validator(v => if v < n { [msg] } else { [] })
}

///|
/// Maximum numeric value (inclusive).
pub fn[V] max_value(
  n : Double,
  message? : String,
) -> @core.Validator[Double, V] {
  let msg = message.unwrap_or("Must be at most \{n}")
  @core.validator(v => if v > n { [msg] } else { [] })
}

///|
/// Regex-free substring/pattern check: the value must contain `pattern`
/// (a pragmatic, dependency-free stand-in for full regex; callers wanting
/// real regex can supply their own closure validator).
pub fn[V] contains(
  pattern : String,
  message? : String,
) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Invalid format")
  @core.validator(v => if v.contains(pattern) { [] } else { [msg] })
}

///|
/// Prefix pattern check.
pub fn[V] starts_with(
  pattern : String,
  message? : String,
) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Invalid format")
  @core.validator(v => if v.has_prefix(pattern) { [] } else { [msg] })
}

///|
/// Custom closure rule: any (value) -> Array[String] predicate becomes a
/// validator (the documented escape hatch for domain logic).
pub fn[A, V] custom(f : (A) -> Array[String]) -> @core.Validator[A, V] {
  @core.validator(f)
}
