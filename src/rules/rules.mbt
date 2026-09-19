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

///|
/// Pragmatic email check: exactly one '@', non-empty local part, a dot in
/// a non-empty domain with a non-empty TLD (user@a.b). Not RFC-complete —
/// use a custom closure validator when you need stricter semantics.
pub fn[V] email(message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Invalid email address")
  @core.validator(v => if email_ok(v) { [] } else { [msg] })
}

///|
fn email_ok(v : String) -> Bool {
  if count_char(v, '@') != 1 {
    return false
  }
  let at = find_char_pos(v, '@')
  let user_part = slice_str(v, 0, at)
  let domain = slice_str(v, at + 1, v.length())
  if user_part.length() == 0 || domain.length() == 0 {
    return false
  }
  if count_char(domain, '.') < 1 {
    return false
  }
  if domain.has_prefix(".") || domain.has_suffix(".") {
    return false
  }
  let last_dot = last_char_pos(domain, '.')
  let tld = slice_str(domain, last_dot + 1, domain.length())
  tld.length() >= 2
}

///|
/// Pragmatic http(s) URL check: scheme://host with a non-empty host that
/// contains a dot (or is "localhost"). Not RFC-complete.
pub fn[V] url(message? : String) -> @core.Validator[String, V] {
  let msg = message.unwrap_or("Invalid URL")
  @core.validator(v => if url_ok(v) { [] } else { [msg] })
}

///|
fn url_ok(v : String) -> Bool {
  let https_ok = v.has_prefix("https://")
  let http_ok = v.has_prefix("http://")
  if !(http_ok || https_ok) {
    return false
  }
  let scheme_len = if https_ok { 8 } else { 7 }
  let rest = slice_str(v, scheme_len, v.length())
  // host ends at the first '/', '?', or ':' (port)
  let mut host = rest
  for stop in ['/', '?', ':'] {
    let p = find_char_pos(host, stop)
    if p >= 0 {
      host = slice_str(host, 0, p)
    }
  }
  if host.length() == 0 {
    return false
  }
  host == "localhost" || count_char(host, '.') >= 1
}

///|
fn count_char(s : String, target : Char) -> Int {
  let mut n = 0
  for ch in s {
    if ch == target {
      n = n + 1
    }
  }
  n
}

///|
fn find_char_pos(s : String, target : Char) -> Int {
  let mut i = 0
  for ch in s {
    if ch == target {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn last_char_pos(s : String, target : Char) -> Int {
  let mut last = -1
  let mut i = 0
  for ch in s {
    if ch == target {
      last = i
    }
    i = i + 1
  }
  last
}

///|
fn slice_str(s : String, from : Int, until : Int) -> String {
  let buf = StringBuilder()
  let mut i = 0
  for ch in s {
    if i >= from && i < until {
      buf.write_char(ch)
    }
    i = i + 1
  }
  buf.to_string()
}
