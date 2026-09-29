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
/// Emit accessors for every concrete struct in the parsed set. Fields
/// whose generated function name collides with an earlier one
/// (`FooBar.x` and `Foo.bar_x` both yield `foo_bar_x_l`) are SKIPPED with
/// a marker comment — a duplicate definition would not compile.
pub fn emit_all(structs : Array[MbtiStruct], core_alias : String) -> String {
  let parts : Array[String] = []
  let used : Array[String] = []
  for st in structs {
    if st.type_params.length() > 0 {
      continue // generic structs need hand-written accessors
    }
    let body : Array[String] = []
    for f in st.fields {
      let fname = "\{snake(st.name)}_\{snake(f.name)}_l"
      if name_used(used, fname) {
        body.push(
          "// skipped \{st.name}.\{f.name}: \{fname} already generated (name collision — write this accessor by hand)",
        )
      } else {
        used.push(fname)
        body.push(emit_lens(st.name, f, core_alias))
      }
    }
    if body.length() > 0 {
      parts.push("// struct \{st.name}")
      for b in body {
        parts.push(b)
      }
    }
  }
  parts.join("\n\n") + "\n"
}

///|
fn name_used(used : Array[String], name : String) -> Bool {
  let mut hit = false
  for u in used {
    if u == name {
      hit = true
    }
  }
  hit
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
