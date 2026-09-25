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
/// extracted.
pub fn parse_mbti(content : String) -> Array[MbtiStruct] {
  let out : Array[MbtiStruct] = []
  let lines : Array[String] = []
  for l in content.split("\n") {
    lines.push(l.to_owned())
  }
  let mut i = 0
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    if line.has_prefix("pub struct ") {
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
fn parse_struct(lines : Array[String], start : Int) -> (MbtiStruct, Int) {
  // header: pub struct Name[T, U] {  (also tolerant of no-space "{")
  let raw = lines[start].trim().to_owned()
  let header = strip_suffix(strip_prefix(raw, "pub struct "), " {")
  let np = split_name_params(header)
  let fields : Array[MbtiField] = []
  let mut i = start + 1
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    if line == "}" {
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
fn split_field(line : String) -> MbtiField? {
  if line.length() == 0 {
    return None
  }
  match find_char(line, ':') {
    Some(idx) => {
      let name = substring(line, 0, idx).trim().to_owned()
      let type_ref = substring(line, idx + 1, line.length()).trim().to_owned()
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
