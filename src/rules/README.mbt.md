# moonform rules — README with doc tests

The `mbt check` blocks below are executed as tests by `moon test`
(documentation that cannot rot). All rules are zero-dependency and
portable across js/wasm/native.

## Required, length, and numeric families

```mbt check
///|
struct Rf {
  rf_name : String
} derive(Eq, Debug)

///|
pub extend Rf with Eq::{not_equal, equal}

///|
pub extend Rf with Debug::{to_repr}

///|
test "doc: rule families judge values" {
  let form = @core.FormApi::make({ rf_name: "", })
  let name = form.field(
    @core.field("name", (v : Rf) => v.rf_name, (_v, n) => { rf_name: n, }),
    on_change_validate=@rules.required().then(@rules.min_length(3)),
  )
  name.mount()
  // chained rules concatenate their errors: "" fails both
  name.set_value("")
  assert_eq(name.meta().errors(), ["Required", "Must be at least 3 characters"])
  name.set_value("ab") // non-empty: only the length rule fires
  assert_eq(name.meta().errors(), ["Must be at least 3 characters"])
  name.set_value("abc")
  assert_eq(name.meta().errors(), [])
}
```

## Format, membership, and custom rules

```mbt check
///|
struct Sel {
  plan : String
  token : String
} derive(Eq, Debug)

///|
pub extend Sel with Eq::{not_equal, equal}

///|
pub extend Sel with Debug::{to_repr}

///|
test "doc: one_of, email, and custom closure rules" {
  // a select field: membership validation
  let plan_rule : @core.Validator[String, Sel] = @rules.one_of([
    "monthly", "yearly",
  ])
  assert_eq(
    @core.Validator::run(plan_rule, "weekly", { plan: "", token: "", }).length(),
    1,
  )
  // format rule with a custom message
  let email_rule : @core.Validator[String, Sel] = @rules.email(
    message="Enter a valid email",
  )
  assert_eq(
    @core.Validator::run(email_rule, "nope", { plan: "", token: "", }),
    ["Enter a valid email"],
  )
  // the escape hatch: any predicate becomes a validator
  let token_rule : @core.Validator[String, Sel] = @rules.custom(v => {
    if v.length() == 6 {
      []
    } else {
      ["Token is 6 characters"]
    }
  })
  assert_eq(@core.Validator::run(token_rule, "abc", { plan: "", token: "", }), [
    "Token is 6 characters",
  ])
}
```
