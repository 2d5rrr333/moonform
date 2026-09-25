// Generated-accessor behavior test (blackbox): the form flow over the
// CLI-generated accessors holds end-to-end.

///|
test "generated: accessors drive a full form flow" {
  assert_true(@generated.run_demo())
}
