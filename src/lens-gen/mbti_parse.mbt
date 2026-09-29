// moonform/lens-gen: .mbti-driven lens generator (MoonBit self-hosted).
//
// Parses `moon info` output (.mbti), extracts pub struct definitions with
// their typed fields, and emits hand-lens code identical in shape to the
// manual `field("name", ...)` accessors. Keys derive from the field name —
// rename a field and regeneration changes the key while stale call sites
// fail to compile (compile-time rename safety).

///|
/// One struct field as declared in .mbti: name + type reference text.
pub struct MbtiField {
  name : String
  type_ref : String
} derive(Eq, Debug)

///|
/// One pub struct declaration parsed from .mbti.
pub struct MbtiStruct {
  name : String
  type_params : Array[String]
  fields : Array[MbtiField]
} derive(Eq, Debug)

///|
/// Parse the struct declarations out of one .mbti document.
/// Comments/blank lines, the package header, imports, values, enums,
/// traits, and method sections are skipped; only `pub struct` blocks are
/// extracted (any `pub` visibility — plain, `pub(all)`, `pub(readonly)`).
pub fn parse_mbti(content : String) -> Array[MbtiStruct] {
  let out : Array[MbtiStruct] = []
  let lines : Array[String] = []
  for l in content.split("\n") {
    lines.push(l.to_owned())
  }
  let mut i = 0
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    if is_struct_header(line) {
      let parsed = parse_struct(lines, i)
      out.push(parsed.0)
      i = parsed.1
    } else {
      i = i + 1
    }
  }
  out
}

///|
/// Is this line a pub struct header? `pub struct`, `pub(all) struct`,
/// `pub(readonly) struct` — `moon info` emits the parenthesized forms for
/// structs whose fields are constructible/updateable externally (the
/// common shape for form value types).
fn is_struct_header(line : String) -> Bool {
  if line.has_prefix("pub struct ") {
    return true
  }
  if line.has_prefix("pub(") {
    // pub(all) struct Foo { / pub(readonly) struct Foo {
    match find_char(line, ')') {
      Some(idx) =>
        substring(line, idx + 1, line.length()).trim().has_prefix("struct ")
      None => false
    }
  } else {
    false
  }
}

///|
fn parse_struct(lines : Array[String], start : Int) -> (MbtiStruct, Int) {
  // header: pub[(...)] struct Name[T, U] {  (any pub visibility; the
  // closing line may carry a derive clause — `} derive(Eq, Debug)`)
  let raw = lines[start].trim().to_owned()
  let after_pub = if raw.has_prefix("pub(") {
    match find_char(raw, ')') {
      Some(idx) => substring(raw, idx + 1, raw.length()).trim().to_owned()
      None => raw
    }
  } else {
    strip_prefix(raw, "pub ").trim().to_owned()
  }
  let header = strip_suffix(strip_prefix(after_pub, "struct "), "{")
    .trim()
    .to_owned()
  let np = split_name_params(header)
  let fields : Array[MbtiField] = []
  let mut i = start + 1
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    // the struct ends at its closing brace — the line may continue with a
    // derive clause (`} derive(Eq, @debug.Debug)`); treating any
    // brace-leading line as the terminator keeps the parser from running
    // past the struct and absorbing the NEXT struct's fields
    if line.has_prefix("}") {
      return ({ name: np.0, type_params: np.1, fields, }, i + 1)
    }
    match split_field(line) {
      Some(f) => fields.push(f)
      None => ()
    }
    i = i + 1
  }
  ({ name: np.0, type_params: np.1, fields, }, i)
}

///|
/// "FormApi[V]" -> ("FormApi", ["V"]); "Key" -> ("Key", [])
fn split_name_params(header : String) -> (String, Array[String]) {
  match find_char(header, '[') {
    Some(idx) => {
      let name = substring(header, 0, idx)
      let inner = substring(header, idx + 1, header.length() - 1)
      let params : Array[String] = []
      for p in inner.split(",") {
        let p = p.trim().to_owned()
        // strip trait bounds: "A : Eq" -> "A"
        match find_char(p, ':') {
          Some(c) => params.push(substring(p, 0, c).trim().to_owned())
          None => params.push(p)
        }
      }
      (name, params)
    }
    None => (header, [])
  }
}

///|
/// "name : Type" -> field record; None when the line is not a field.
/// `mut` fields are ordinary fields to lenses (struct update syntax
/// writes them the same way) — the modifier is stripped.
fn split_field(line : String) -> MbtiField? {
  if line.length() == 0 {
    return None
  }
  let body = strip_prefix(line, "mut ").trim().to_owned()
  match find_char(body, ':') {
    Some(idx) => {
      let name = substring(body, 0, idx).trim().to_owned()
      let type_ref = substring(body, idx + 1, body.length()).trim().to_owned()
      if name.length() > 0 && type_ref.length() > 0 && is_ident(name) {
        Some({ name, type_ref, })
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn is_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for ch in s {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_'
    if !ok {
      return false
    }
  }
  true
}

// -- tiny string helpers (String lacks replace/find in core) -----------------

///|
fn find_char(s : String, target : Char) -> Int? {
  let mut i = 0
  for ch in s {
    if ch == target {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn substring(s : String, from : Int, until : Int) -> String {
  let out : Array[Char] = []
  let mut i = 0
  for ch in s {
    if i >= from && i < until {
      out.push(ch)
    }
    i = i + 1
  }
  let buf = StringBuilder()
  for ch in out {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
fn strip_prefix(s : String, prefix : String) -> String {
  if s.has_prefix(prefix) {
    substring(s, prefix.length(), s.length())
  } else {
    s
  }
}

///|
fn strip_suffix(s : String, suffix : String) -> String {
  if s.has_suffix(suffix) {
    substring(s, 0, s.length() - suffix.length())
  } else {
    s
  }
}

///|
pub extend MbtiField with Debug::{to_repr}

///|
pub extend MbtiField with Eq::{not_equal, equal}

///|
pub extend MbtiStruct with Debug::{to_repr}

///|
pub extend MbtiStruct with Eq::{not_equal, equal}
