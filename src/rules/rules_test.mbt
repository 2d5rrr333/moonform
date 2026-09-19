// rules package: behavior tests for the built-in rules (blackbox — public
// API only). Mirrors the rules spec scenarios.

///|
struct DummyForm {
  unused : Int
} derive(Eq, Debug)

///|
fn dummy() -> DummyForm {
  { unused: 0, }
}

///|
test "required rejects empty and accepts non-empty" {
  let r : @core.Validator[String, DummyForm] = required()
  assert_eq(@core.Validator::run(r, "", dummy()), ["Required"])
  assert_eq(@core.Validator::run(r, "x", dummy()), [])
  let custom_msg : @core.Validator[String, DummyForm] = required(
    message="Name is required",
  )
  assert_eq(@core.Validator::run(custom_msg, "", dummy()), ["Name is required"])
}

///|
test "required_array enforces at least one element" {
  let r : @core.Validator[Array[String], DummyForm] = required_array()
  assert_eq(@core.Validator::run(r, [], dummy()), ["Required"])
  assert_eq(@core.Validator::run(r, ["a"], dummy()), [])
}

///|
test "min_length boundary is inclusive" {
  let r : @core.Validator[String, DummyForm] = min_length(3)
  assert_eq(@core.Validator::run(r, "ab", dummy()), [
    "Must be at least 3 characters",
  ])
  assert_eq(@core.Validator::run(r, "abc", dummy()), [])
  assert_eq(@core.Validator::run(r, "abcd", dummy()), [])
}

///|
test "max_length boundary is inclusive" {
  let r : @core.Validator[String, DummyForm] = max_length(3)
  assert_eq(@core.Validator::run(r, "abcd", dummy()), [
    "Must be at most 3 characters",
  ])
  assert_eq(@core.Validator::run(r, "abc", dummy()), [])
}

///|
test "min_value / max_value boundaries are inclusive" {
  let minr : @core.Validator[Double, DummyForm] = min_value(1.5)
  assert_eq(@core.Validator::run(minr, 1.4, dummy()), ["Must be at least 1.5"])
  assert_eq(@core.Validator::run(minr, 1.5, dummy()), [])
  let maxr : @core.Validator[Double, DummyForm] = max_value(10.0)
  assert_eq(@core.Validator::run(maxr, 10.1, dummy()), ["Must be at most 10"])
  assert_eq(@core.Validator::run(maxr, 10.0, dummy()), [])
}

///|
test "contains and starts_with pattern checks" {
  let c : @core.Validator[String, DummyForm] = contains("@")
  assert_eq(@core.Validator::run(c, "root@x.io", dummy()), [])
  assert_eq(@core.Validator::run(c, "root.x.io", dummy()), ["Invalid format"])
  let p : @core.Validator[String, DummyForm] = starts_with("https://")
  assert_eq(@core.Validator::run(p, "https://x", dummy()), [])
  assert_eq(@core.Validator::run(p, "http://x", dummy()), ["Invalid format"])
}

///|
test "custom closure rule" {
  let even : @core.Validator[Int, DummyForm] = custom(n => {
    if n % 2 == 0 {
      []
    } else {
      ["must be even"]
    }
  })
  assert_eq(@core.Validator::run(even, 2, dummy()), [])
  assert_eq(@core.Validator::run(even, 3, dummy()), ["must be even"])
}

///|
test "min_int / max_int boundaries are inclusive" {
  let minr : @core.Validator[Int, DummyForm] = min_int(3)
  assert_eq(@core.Validator::run(minr, 2, dummy()), ["Must be at least 3"])
  assert_eq(@core.Validator::run(minr, 3, dummy()), [])
  let maxr : @core.Validator[Int, DummyForm] = max_int(10)
  assert_eq(@core.Validator::run(maxr, 11, dummy()), ["Must be at most 10"])
  assert_eq(@core.Validator::run(maxr, 10, dummy()), [])
}

///|
test "equals accepts only the expected constant" {
  let r : @core.Validator[String, DummyForm] = equals("yes")
  assert_eq(@core.Validator::run(r, "yes", dummy()), [])
  assert_eq(@core.Validator::run(r, "no", dummy()), ["Values do not match"])
}

///|
test "must_be_true enforces checked boxes" {
  let r : @core.Validator[Bool, DummyForm] = must_be_true()
  assert_eq(@core.Validator::run(r, true, dummy()), [])
  assert_eq(@core.Validator::run(r, false, dummy()), [
    "This field must be checked",
  ])
}

///|
test "non_blank rejects whitespace-only strings" {
  let r : @core.Validator[String, DummyForm] = non_blank()
  assert_eq(@core.Validator::run(r, "ok", dummy()), [])
  assert_eq(@core.Validator::run(r, "", dummy()), ["Must not be blank"])
  assert_eq(@core.Validator::run(r, "   ", dummy()), ["Must not be blank"])
  assert_eq(@core.Validator::run(r, " \t\n ", dummy()), ["Must not be blank"])
}

///|
test "numeric accepts integers with optional sign" {
  let r : @core.Validator[String, DummyForm] = numeric()
  assert_eq(@core.Validator::run(r, "123", dummy()), [])
  assert_eq(@core.Validator::run(r, "-42", dummy()), [])
  assert_eq(@core.Validator::run(r, "12a", dummy()), ["Must be a number"])
  assert_eq(@core.Validator::run(r, "1-2", dummy()), ["Must be a number"])
  assert_eq(@core.Validator::run(r, "", dummy()), ["Must be a number"])
}

///|
struct Login {
  email : String
} derive(Eq, Debug)

///|
fn login_email_l() -> @core.Lens[Login, String] {
  @core.field("email", l => l.email, (_l, e) => { email: e, })
}

///|
test "rules chain and run through the core protocol" {
  // wire into a real form: required + min_length on a login email
  let form = @core.FormApi::make({ email: "", })
  let required_rule : @core.Validator[String, Login] = required()
  let min3_rule : @core.Validator[String, Login] = min_length(3)
  let email = form.field(
    login_email_l(),
    on_change_validate=required_rule.then(min3_rule),
  )
  email.mount()
  email.set_value("")
  // chained rules all run and errors concatenate (rules spec: 规则组合)
  assert_eq(email.meta().errors(), ["Required", "Must be at least 3 characters"])
  email.set_value("ab")
  assert_eq(email.meta().errors(), ["Must be at least 3 characters"])
  email.set_value("abc")
  assert_eq(email.meta().errors(), [])
}
