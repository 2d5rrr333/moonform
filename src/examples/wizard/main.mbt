// Wizard example: multi-step form with FormGroupApi — per-step group
// validation (group errors + error distribution to child fields), group
// submissions that never touch the parent form's submit state, and a final
// whole-form submit gated on every step being valid.
// Headless verification run: `moon run src/examples/wizard --target js`.

///|
struct Account {
  username : String
  email : String
} derive(Eq, Debug)

///|
struct Profile {
  nickname : String
} derive(Eq, Debug)

///|
struct WizardValues {
  account : Account
  profile : Profile
} derive(Eq, Debug)

///|
struct Tally {
  mut n : Int
}

///|
fn account_l() -> @core.Lens[WizardValues, Account] {
  @core.field("account", (v : WizardValues) => v.account, (v, a) => {
    ..v,
    account: a,
  })
}

///|
fn profile_l() -> @core.Lens[WizardValues, Profile] {
  @core.field("profile", (v : WizardValues) => v.profile, (v, p) => {
    ..v,
    profile: p,
  })
}

///|
fn username_l() -> @core.Lens[WizardValues, String] {
  account_l().compose(
    @core.field("username", (a : Account) => a.username, (a, u) => {
      ..a,
      username: u,
    }),
  )
}

///|
fn email_l() -> @core.Lens[WizardValues, String] {
  account_l().compose(
    @core.field("email", (a : Account) => a.email, (a, e) => { ..a, email: e, }),
  )
}

///|
fn nickname_l() -> @core.Lens[WizardValues, String] {
  profile_l().compose(
    @core.field("nickname", (p : Profile) => p.nickname, (_p, n) => {
      nickname: n,
    }),
  )
}

///|
/// Step 1 validator: a field error (username, distributed to the field)
/// plus a group-level error (email) in one result — both channels at once.
fn account_validator() -> @core.GroupValidator[Account, WizardValues] {
  @core.group_validator_value(a => {
    if a.username == "" && !a.email.contains("@") {
      @core.GroupValidationResult::group_and_fields("Email must contain @", [
        (@core.Key::field("username"), "Username is required"),
      ])
    } else if a.username == "" {
      @core.GroupValidationResult::fields([
        (@core.Key::field("username"), "Username is required"),
      ])
    } else if !a.email.contains("@") {
      @core.GroupValidationResult::group_error("Email must contain @")
    } else {
      @core.GroupValidationResult::valid()
    }
  })
}

///|
fn profile_validator() -> @core.GroupValidator[Profile, WizardValues] {
  @core.group_validator_value(p => {
    if p.nickname.length() < 3 {
      @core.GroupValidationResult::fields([
        (@core.Key::field("nickname"), "Nickname needs 3+ characters"),
      ])
    } else {
      @core.GroupValidationResult::valid()
    }
  })
}

///|
fn main raise {
  let form = @core.FormApi::make({
    account: { username: "", email: "", },
    profile: { nickname: "", },
  })
  let step1 = form.group(account_l(), on_submit_validate=account_validator())
  let step2 = form.group(profile_l(), on_submit_validate=profile_validator())
  let username = form.field(username_l())
  let email = form.field(email_l())
  let nickname = form.field(nickname_l())
  step1.mount()
  step2.mount()
  username.mount()
  email.mount()
  nickname.mount()
  // the React adapter reads group state through a GroupBridge (here in
  // headless mode; components get the same snapshot via use_group)
  let step1_view = @formreact.GroupBridge::make(step1)
  step1_view.attach()
  // -- step 1: both channels fail ------------------------------------------
  let step1_done = Tally::make()
  step1_view.submit(
    on_group_submit=(_v, _meta) => step1_done.n = step1_done.n + 1,
    on_group_submit_invalid=() => (),
  )
  let s = step1_view.state()
  assert_eq(step1_done.n, 0) // blocked
  assert_false(s.is_fields_valid) // distributed username error
  assert_false(s.is_group_valid) // group-level email error
  assert_eq(username.meta().errors(), ["Username is required"])
  assert_eq(s.errors, ["Email must contain @"])
  // step 2 is untouched by step 1's failure
  assert_eq(nickname.meta().errors(), [])
  // -- fix both, resubmit step 1 -------------------------------------------
  username.set_value("moonbit")
  email.set_value("moon@example.com")
  step1_view.submit(
    on_group_submit=(_v, _meta) => step1_done.n = step1_done.n + 1,
    on_group_submit_invalid=() => (),
  )
  let s2 = step1_view.state()
  assert_eq(step1_done.n, 1) // step 1 passed
  assert_true(s2.is_valid) // snapshot recovered after the fix
  assert_eq(form.submission_attempts(), 0) // the form never submitted
  assert_false(form.is_submitted())
  // -- step 2: own validation, step 1 unaffected ---------------------------
  let step2_done = Tally::make()
  step2.handle_submit(
    on_group_submit=(_v, _meta) => step2_done.n = step2_done.n + 1,
    on_group_submit_invalid=() => (),
  )
  assert_eq(step2_done.n, 0) // blocked: nickname too short
  assert_eq(nickname.meta().errors(), ["Nickname needs 3+ characters"])
  // step 1's counter stays at its own 2 attempts (blocked + passed);
  // step 2's submission does not bump it
  assert_eq(step1.submission_attempts(), 2)
  nickname.set_value("moonman")
  step2.handle_submit(
    on_group_submit=(_v, _meta) => step2_done.n = step2_done.n + 1,
    on_group_submit_invalid=() => (),
  )
  assert_eq(step2_done.n, 1)
  // -- final whole-form submit ---------------------------------------------
  let form_done = Tally::make()
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_values, done) => {
        form_done.n = form_done.n + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  assert_eq(form_done.n, 1)
  assert_true(form.is_submit_successful())
  println("wizard example: all checks passed")
}

///|
fn Tally::make() -> Tally {
  { n: 0, }
}

///|
pub extend Account with Debug::{to_repr}

///|
pub extend Account with Eq::{not_equal, equal}

///|
pub extend Profile with Debug::{to_repr}

///|
pub extend Profile with Eq::{not_equal, equal}

///|
pub extend WizardValues with Debug::{to_repr}

///|
pub extend WizardValues with Eq::{not_equal, equal}
