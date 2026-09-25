# moonform schema — README with doc tests

The `mbt check` blocks below are executed as tests by `moon test`
(documentation that cannot rot).

## A compiled schema as a per-field validator

```mbt check
///|
struct DocLogin {
  username : String
  password : String
} derive(Eq, ToJson, Debug)

///|
pub extend DocLogin with Eq::{not_equal, equal}

///|
pub extend DocLogin with ToJson::{to_json}

///|
pub extend DocLogin with Debug::{to_repr}

///|
fn doc_login_username_l() -> @core.Lens[DocLogin, String] {
  @core.field("username", (v : DocLogin) => v.username, (v, u) => {
    ..v,
    username: u,
  })
}

///|
fn doc_login_password_l() -> @core.Lens[DocLogin, String] {
  @core.field("password", (v : DocLogin) => v.password, (v, p) => {
    ..v,
    password: p,
  })
}

///|
test "doc: schema_field_validator feeds the field's own error slot" {
  let s = @builder.object({
    "username": @builder.string().min_len(2),
    "password": @builder.string().min_len(8),
  }).compile() catch {
    _ => abort("schema compile failed")
  }
  let form = @core.FormApi::make({ username: "", password: "", })
  let username = form.field(
    doc_login_username_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "username",
      doc_login_username_l(),
    ),
  )
  let password = form.field(
    doc_login_password_l(),
    on_change_validate=@schema.schema_field_validator(
      s,
      "password",
      doc_login_password_l(),
    ),
  )
  username.mount()
  password.mount()
  // each field sees only its own JSON-Pointer ("/username", "/password")
  username.set_value("x")
  password.set_value("short")
  assert_eq(username.meta().errors().length(), 1)
  assert_eq(password.meta().errors().length(), 1)
  // fixing each field clears its own slot only
  username.set_value("ok")
  assert_eq(username.meta().errors(), [])
  assert_eq(password.meta().errors().length(), 1)
}
```

## A compiled schema as a group validator

```mbt check
///|
struct DocAccount {
  username : String
  email : String
} derive(Eq, ToJson, Debug)

///|
pub extend DocAccount with Eq::{not_equal, equal}

///|
pub extend DocAccount with ToJson::{to_json}

///|
pub extend DocAccount with Debug::{to_repr}

///|
struct DocWizard {
  account : DocAccount
} derive(Eq, ToJson, Debug)

///|
pub extend DocWizard with Eq::{not_equal, equal}

///|
pub extend DocWizard with ToJson::{to_json}

///|
pub extend DocWizard with Debug::{to_repr}

///|
fn doc_account_l() -> @core.Lens[DocWizard, DocAccount] {
  @core.field("account", (v : DocWizard) => v.account, (_v, a) => {
    account: a,
  })
}

///|
fn doc_username_l() -> @core.Lens[DocWizard, String] {
  doc_account_l().compose(
    @core.field("username", (a : DocAccount) => a.username, (a, u) => {
      ..a,
      username: u,
    }),
  )
}

///|
fn doc_email_l() -> @core.Lens[DocWizard, String] {
  doc_account_l().compose(
    @core.field("email", (a : DocAccount) => a.email, (a, e) => {
      ..a,
      email: e,
    }),
  )
}

///|
test "doc: schema group validator distributes errors to child fields" {
  let s = @builder.object({
    "username": @builder.string().min_len(2),
    "email": @builder.string().email(),
  }).compile() catch {
    _ => abort("schema compile failed")
  }
  let form = @core.FormApi::make({ account: { username: "x", email: "nope", }, })
  let account = form.group(
    doc_account_l(),
    on_submit_validate=@schema.schema_group_validator(s),
  )
  let username = form.field(doc_username_l())
  let email = form.field(doc_email_l())
  account.mount()
  username.mount()
  email.mount()
  account.handle_submit()
  // JSON-Pointer paths distributed to the child fields' slots
  inspect(username.meta().errors().length(), content="1")
  inspect(email.meta().errors().length(), content="1")
  assert_false(account.is_fields_valid())
  // fixing the values clears the distributed errors
  username.set_value("moonbit")
  email.set_value("moon@example.com")
  account.handle_submit()
  assert_true(account.is_valid())
}
```
