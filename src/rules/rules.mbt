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

///|
/// Integer minimum (inclusive) — for whole-number fields.
pub fn[V] min_int(n : Int, message? : String) -> @core.Validator[Int, V] {
  let msg = message.unwrap_or("Must be at least \{n}")
  @core.validator(v => if v < n { [msg] } else { [] })
}

///|
/// Integer maximum (inclusive).
pub fn[V] max_int(n : Int, message? : String) -> @core.Validator[Int, V] {
  let msg = message.unwrap_or("Must be at most \{n}")
  @core.validator(v => if v > n { [msg] } else { [] })
}

///|
/// Value must equal the expected constant (confirmation fields etc.).
pub fn[A : Eq, V] equals(
  expected : A,
  message? : String,
) -> @core.Validator[A, V] {
  let msg = message.unwrap_or("Values do not match")
  @core.validator(v => if v == expected { [] } else { [msg] })
}

///|
/// Boolean must be true (terms-accepted checkboxes etc.).
pub fn[V] must_be_true(message? : String) -> @core.Validator[Bool, V] {
  let msg = message.unwrap_or("This field must be checked")
  @core.validator(v => if v { [] } else { [msg] })
}

///|
/// Trimmed string must be non-blank (rejects "   " where required()
/// accepts it only for "").
pub fn[V] non_blank(message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Must not be blank")
  @core.validator(v => {
    let mut all_space = true
    for ch in v {
      if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
        all_space = false
      }
    }
    if all_space {
      [msg]
    } else {
      []
    }
  })
}

///|
/// Numeric string check (digits, optional leading '-') — dependency-free
/// stand-in for full number parsing.
pub fn[V] numeric(message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Must be a number")
  @core.validator(v => {
    if v.length() == 0 {
      return [msg]
    }
    let mut i = 0
    let mut ok = true
    for ch in v {
      let digit = ch >= '0' && ch <= '9'
      let sign = i == 0 && ch == '-'
      if !(digit || sign) {
        ok = false
      }
      i = i + 1
    }
    if ok {
      []
    } else {
      [msg]
    }
  })
}
