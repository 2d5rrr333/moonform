// lens-gen entry: .mbti content in, lens source out. Drive it from a
// MoonBit script/test (zero third-party deps; no fs in core):
//
//   let out = @lens_gen.generate(mbti_text, "@core")

///|
/// Parse .mbti content and emit lens accessor source for every concrete
/// (non-generic) pub struct.
pub fn generate(mbti_content : String, core_alias : String) -> String {
  let structs = parse_mbti(mbti_content)
  emit_all(structs, core_alias)
}

///|
/// Structs parsed from the content (for inspection/tests).
pub fn parse_only(mbti_content : String) -> Array[MbtiStruct] {
  parse_mbti(mbti_content)
}
