// one_of / one_of_str: enum-membership validation.

///|
test "one_of accepts members and rejects non-members" {
  let r : @core.Validator[String, String] = @rules.one_of([
    "red", "green", "blue",
  ])
  assert_eq(@core.Validator::run(r, "green", "form"), [])
  assert_eq(@core.Validator::run(r, "yellow", "form"), [
    "Must be one of the allowed values",
  ])
}

///|
test "one_of honors custom messages" {
  let r : @core.Validator[String, String] = @rules.one_of(
    ["a", "b"],
    message="Pick a supported option",
  )
  assert_eq(@core.Validator::run(r, "c", "form"), ["Pick a supported option"])
}

///|
test "one_of works over non-string values" {
  let r : @core.Validator[Int, String] = @rules.one_of([1, 2, 3])
  assert_eq(@core.Validator::run(r, 2, "form"), [])
  assert_eq(@core.Validator::run(r, 9, "form").length(), 1)
}

///|
test "one_of_str matches one_of behavior" {
  let r : @core.Validator[String, String] = @rules.one_of_str([
    "monthly", "yearly",
  ])
  assert_eq(@core.Validator::run(r, "yearly", "form"), [])
  assert_eq(@core.Validator::run(r, "weekly", "form").length(), 1)
}

///|
test "one_of with an empty allowed set rejects everything" {
  let r : @core.Validator[String, String] = @rules.one_of([])
  assert_eq(@core.Validator::run(r, "anything", "form").length(), 1)
}
