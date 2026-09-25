// Lens code emission from parsed .mbti structs.

///|
/// Emit one accessor function for `struct_name.field` as MoonBit source.
/// Shape mirrors the hand-written convention (and `moon fmt` output —
/// the regenerated files pass format checks unchanged):
///
///   ///|
///   fn loginform_email_l() -> @core.Lens[LoginForm, String] {
///     @core.field("email", v => v.email, (v, x) => { ..v, email: x, })
///   }
///
/// Non-generic structs only (form value types are concrete); structs with
/// type parameters are skipped by `emit_for_struct` returning "".
pub fn emit_lens(
  struct_name : String,
  field : MbtiField,
  core_alias : String,
) -> String {
  let fname = "\{snake(struct_name)}_\{snake(field.name)}_l"
  let lines : Array[String] = [
    "///|",
    "fn \{fname}() -> \{core_alias}.Lens[\{struct_name}, \{field.type_ref}] {",
    "  \{core_alias}.field(\"\{field.name}\", v => v.\{field.name}, (v, x) => { ..v, \{field.name}: x, })",
    "}",
  ]
  lines.join("\n")
}

///|
/// Emit accessors for one struct (empty string when it has type params —
/// generic structs need hand-written accessors).
pub fn emit_for_struct(st : MbtiStruct, core_alias : String) -> String {
  if st.type_params.length() > 0 {
    return ""
  }
  let parts : Array[String] = []
  for f in st.fields {
    parts.push(emit_lens(st.name, f, core_alias))
  }
  parts.join("\n\n")
}

///|
/// Emit accessors for every concrete struct in the parsed set.
pub fn emit_all(structs : Array[MbtiStruct], core_alias : String) -> String {
  let parts : Array[String] = []
  for st in structs {
    let code = emit_for_struct(st, core_alias)
    if code.length() > 0 {
      parts.push("// struct \{st.name}")
      parts.push(code)
    }
  }
  parts.join("\n\n") + "\n"
}

///|
/// snake_case conversion used for function names.
pub fn snake(s : String) -> String {
  let mut out = ""
  for ch in s {
    if ch >= 'A' && ch <= 'Z' {
      if out.length() > 0 {
        out = out + "_"
      }
      out = out + char_lower(ch)
    } else {
      out = out + "\{ch}"
    }
  }
  out
}

///|
fn char_lower(ch : Char) -> String {
  let code = ch.to_int()
  if code >= 65 && code <= 90 {
    // 'A'..'Z' -> 'a'..'z'
    let lower = (code + 32).unsafe_to_char()
    "\{lower}"
  } else {
    "\{ch}"
  }
}
