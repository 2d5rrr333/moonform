// lens-gen: parser and emitter behavior. The parser runs against the
// authentic core .mbti grammar (struct blocks, generics, trait bounds).

///|
fn core_mbti_sample() -> String {
  let lines : Array[String] = [
    "// Generated using `moon info`, DON'T EDIT IT", "package \"2d5rrr333/moonform/core\"",
    "", "// Values", "pub fn[S, A] field(String, (S) -> A, (S, A) -> S) -> Lens[S, A]",
    "", "// Errors", "", "// Types and methods", "pub enum Seg {", "  Field(String)",
    "  Idx(Int)", "} derive(Eq, @debug.Debug)", "", "pub struct Lens[S, A] {", "  key : Key",
    "  get : (S) -> A", "  set : (S, A) -> S", "}", "", "pub struct FieldMetaState {",
    "  is_touched : Bool", "  error_map : ErrorMap", "  array_version : Int", "}",
    "", "pub struct FormApi[V] {", "  mut default_values : V", "  meta : MetaStore",
    "}", "", "pub struct Key {", "  segs : Array[Seg]", "}",
  ]
  lines.join("\n")
}

///|
test "parser: extracts structs, skips enums/values/imports" {
  let structs = parse_only(core_mbti_sample())
  // Seg enum skipped; Lens / FieldMetaState / FormApi / Key parsed
  assert_eq(structs.length(), 4)
  let names = structs.map(s => s.name)
  assert_true(names.contains("Lens"))
  assert_true(names.contains("FieldMetaState"))
  assert_true(names.contains("FormApi"))
  assert_true(names.contains("Key"))
}

///|
test "parser: fields with types, generics on header, mut modifier" {
  let structs = parse_only(core_mbti_sample())
  let lens = find_struct(structs, "Lens")
  let fms = find_struct(structs, "FieldMetaState")
  let form_api = find_struct(structs, "FormApi")
  assert_eq(lens.type_params, ["S", "A"])
  assert_eq(lens.fields.length(), 3)
  assert_eq(lens.fields[0].name, "key")
  assert_eq(lens.fields[0].type_ref, "Key")
  assert_eq(fms.type_params, [])
  assert_eq(fms.fields.length(), 3)
  assert_eq(fms.fields[1].name, "error_map")
  assert_eq(fms.fields[1].type_ref, "ErrorMap")
  // `mut` fields are ordinary fields to lenses — the modifier is stripped
  // (they used to be silently dropped)
  assert_eq(form_api.fields.length(), 2)
  assert_eq(form_api.fields[0].name, "default_values")
  assert_eq(form_api.fields[0].type_ref, "V")
}

///|
/// The authentic `moon info` shapes the parser must survive: derive
/// clauses on CLOSING lines, pub(all) visibility, several structs in a
/// row. (The derive closing line used to run the parser past the struct,
/// absorbing the NEXT struct's fields and duplicating accessors.)
fn derive_mbti_sample() -> String {
  let lines : Array[String] = [
    "// Generated using `moon info`, DON'T EDIT IT", "package \"2d5rrr333/moonform/examples/generated\"",
    "", "// Types and methods", "pub struct Profile {", "  nickname : String", "  age : Int",
    "} derive(Eq, @debug.Debug)", "pub(all) struct Address {", "  city : String",
    "  zip : Int", "} derive(Eq, @debug.Debug)", "pub struct Plain {", "  note : String",
    "}", "", "pub fn Profile::equal(Self, Self) -> Bool",
  ]
  lines.join("\n")
}

///|
test "parser: derive closing lines end the struct — no field absorption" {
  let structs = parse_only(derive_mbti_sample())
  assert_eq(structs.length(), 3)
  let profile = find_struct(structs, "Profile")
  let address = find_struct(structs, "Address")
  let plain = find_struct(structs, "Plain")
  // each struct keeps EXACTLY its own fields (the old parser absorbed
  // Address's fields into Profile after its derive closing line)
  assert_eq(profile.fields.length(), 2)
  assert_eq(profile.fields[0].name, "nickname")
  assert_eq(address.fields.length(), 2)
  assert_eq(address.fields[0].name, "city")
  assert_eq(address.fields[1].type_ref, "Int")
  assert_eq(plain.fields.length(), 1)
  assert_eq(plain.fields[0].name, "note")
  // the method line after the last struct is never a field
  assert_false(plain.fields[0].name == "equal")
}

///|
test "parser: pub(all) structs are extracted (form value types)" {
  let structs = parse_only(derive_mbti_sample())
  let address = find_struct(structs, "Address")
  assert_eq(address.type_params, [])
  // and the emitter covers them like any concrete struct
  let code = emit_all(structs, "@core")
  assert_true(
    code.contains("fn address_city_l() -> @core.Lens[Address, String]"),
  )
}

///|
test "emitter: name collisions are skipped with a marker, never duplicated" {
  // FooBar.x and Foo.bar_x both snake-case to foo_bar_x — a duplicate
  // function would not compile
  let lines : Array[String] = [
    "pub struct FooBar {", "  x : Int", "}", "pub struct Foo {", "  bar_x : Int",
    "}",
  ]
  let structs = parse_only(lines.join("\n"))
  let code = emit_all(structs, "@core")
  // exactly one definition of the colliding name
  let mut defs = 0
  for l in code.split("\n") {
    if l.to_owned().contains("fn foo_bar_x_l()") {
      defs = defs + 1
    }
  }
  assert_eq(defs, 1)
  // the loser is skipped with an explanatory comment
  assert_true(
    code.contains("// skipped Foo.bar_x: foo_bar_x_l already generated"),
  )
}

///|
fn find_struct(structs : Array[MbtiStruct], name : String) -> MbtiStruct {
  for s in structs {
    if s.name == name {
      return s
    }
  }
  abort("missing struct \{name}")
}

///|
test "emitter: concrete struct emits an accessor per field" {
  let structs = parse_only(core_mbti_sample())
  let code = emit_all(structs, "@core")
  // FieldMetaState accessors present with snake_case names
  assert_true(code.contains("fn field_meta_state_is_touched_l()"))
  assert_true(code.contains("@core.Lens[FieldMetaState, Bool]"))
  assert_true(code.contains("\"is_touched\""))
  assert_true(code.contains("v.is_touched"))
  // generic structs (Lens, FormApi) are skipped
  assert_false(code.contains("Lens[S, A]"))
  assert_false(code.contains("FormApi[V]"))
}

///|
test "emitter: generated accessor shape matches the manual convention" {
  let structs = parse_only(core_mbti_sample())
  let code = emit_all(structs, "@core")
  // fmt-stable shape: ///| marker + trailing comma in the record update
  let expected = [
    "///|", "fn key_segs_l() -> @core.Lens[Key, Array[Seg]] {", "  @core.field(\"segs\", v => v.segs, (v, x) => { ..v, segs: x, })",
    "}",
  ].join("\n")
  assert_true(code.contains(expected))
}

///|
test "generator: end-to-end content to source" {
  let out = generate(core_mbti_sample(), "@core")
  assert_true(out.length() > 0)
  assert_true(out.has_prefix("// struct"))
}

///|
test "generator: idempotent — same input, same output" {
  let a = generate(core_mbti_sample(), "@core")
  let b = generate(core_mbti_sample(), "@core")
  assert_eq(a, b)
}

///|
test "generator: rename changes the key and the function name" {
  // renaming a field in the .mbti changes the emitted key — stale call
  // sites referencing the old accessor fail to compile (rename safety)
  let renamed = core_mbti_sample().replace(
    old="  is_touched : Bool",
    new="  is_touched_renamed : Bool",
  )
  let out = generate(renamed, "@core")
  assert_true(out.contains("\"is_touched_renamed\""))
  assert_false(out.contains("\"is_touched\"")) // old key gone
  assert_true(out.contains("fn field_meta_state_is_touched_renamed_l()"))
}

///|
test "snake: camel case to snake case" {
  assert_eq(snake("FieldMetaState"), "field_meta_state")
  assert_eq(snake("Key"), "key")
  assert_eq(snake("errorMap"), "error_map")
}
