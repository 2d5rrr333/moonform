// README quick-start verifier: the five complete-able code blocks from the
// main README, compiled and behavior-asserted against the PUBLISHED
// mooncakes package (not the workspace source). If a README example drifts
// from reality, this fails. js target only (schema/react blocks need js).
//
// Run: moon run src/readme-verify --target js   (from the repo root, after
// `moon update` — depends on the published 2d5rrr333/moonform)

///|
struct Login {
  email : String
  password : String
} derive(Eq, Debug)

///|
pub extend Login with Eq::{not_equal, equal}

///|
pub extend Login with Debug::{to_repr}

///|
fn email_l() -> @core.Lens[Login, String] {
  @core.field("email", v => v.email, (v, e) => { ..v, email: e, })
}

///|
struct Friend {
  fname : String
} derive(Eq, Debug)

///|
pub extend Friend with Eq::{not_equal, equal}

///|
pub extend Friend with Debug::{to_repr}

///|
struct RosterForm {
  friends : Array[Friend]
} derive(Eq, Debug)

///|
pub extend RosterForm with Eq::{not_equal, equal}

///|
pub extend RosterForm with Debug::{to_repr}

///|
fn friends_l() -> @core.Lens[RosterForm, Array[Friend]] {
  @core.field("friends", (v : RosterForm) => v.friends, (_v, xs) => {
    friends: xs,
  })
}

///|
struct Step {
  name : String
} derive(Eq, ToJson, Debug)

///|
pub extend Step with Eq::{not_equal, equal}

///|
pub extend Step with ToJson::{to_json}

///|
pub extend Step with Debug::{to_repr}

///|
struct WizardForm {
  step1 : Step
} derive(Eq, Debug)

///|
pub extend WizardForm with Eq::{not_equal, equal}

///|
pub extend WizardForm with Debug::{to_repr}

///|
fn step1_l() -> @core.Lens[WizardForm, Step] {
  @core.field("step1", (v : WizardForm) => v.step1, (_v, s) => { step1: s, })
}

///|
fn step_name_l() -> @core.Lens[Step, String] {
  @core.field("name", (s : Step) => s.name, (_s, n) => { name: n, })
}

///|
priv struct RvCounter {
  mut n : Int
}

///|
fn main {
  // ---- README 快速开始 (block 1) ----
  let form = @core.FormApi::make({ email: "", password: "", })
  let email = form.field(
    email_l(),
    on_change_validate=@rules.required().then(@rules.min_length(3)),
  )
  email.mount()
  email.set_value("ab")
  if email.meta().errors() != ["Must be at least 3 characters"] {
    println("readme-verify FAIL: block1 errors mismatch")
    return
  }
  email.handle_blur()
  if !(email.meta().is_touched && email.meta().is_blurred) {
    println("readme-verify FAIL: block1 blur flags")
    return
  }
  let password = form.field(
    @core.field("password", (v : Login) => v.password, (v, p) => {
      ..v,
      password: p,
    }),
    on_submit_validate=@rules.required(),
  )
  password.mount()
  let blocked : RvCounter = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit_invalid: Some(_ => blocked.n = blocked.n + 1),
  })
  if blocked.n != 1 {
    println("readme-verify FAIL: block1 submit gate")
    return
  }
  // ---- 数组字段 (block 2) ----
  let rform = @core.FormApi::make({
    friends: [{ fname: "alice", }, { fname: "bob", }, { fname: "carol", }],
  })
  let friend = { fname: "dave", }
  rform.push_value(friends_l(), friend)
  rform.remove_value(friends_l(), 0) // friends[1].name errors migrate down
  rform.swap_values(friends_l(), 0, 2)
  if rform.get_value(friends_l()).length() != 3 {
    println("readme-verify FAIL: block2 length")
    return
  }
  // ---- 异步校验 (block 3) ----
  let clock = @core.VirtualClock::make()
  let values : Login = { email: "", password: "", }
  let aform = @core.FormApi::make(values).with_clock(clock.clock())
  let afield = aform.field(
    email_l(),
    on_change_async_debounce_ms=500,
    on_change_async_validate=@core.async_validator((value, _clock, done) => {
      if value == "taken" {
        done(["already taken"])
      } else {
        done([])
      }
    }),
  )
  afield.mount()
  afield.set_value("x")
  clock.run_all()
  if afield.meta().has_errors() {
    println("readme-verify FAIL: block3 unexpected errors")
    return
  }
  afield.set_value("taken")
  clock.run_all()
  if afield.meta().errors() != ["already taken"] {
    println("readme-verify FAIL: block3 async error missing")
    return
  }
  // ---- 字段组 (block 4) ----
  let wform = @core.FormApi::make({ step1: { name: "", }, })
  let step1 = wform.group(
    step1_l(),
    on_submit_validate=@core.group_validator_value(g => {
      if g.name == "" {
        @core.GroupValidationResult::group_and_fields("Step incomplete", [
          (@core.Key::field("name"), "Name is required"),
        ])
      } else {
        @core.GroupValidationResult::valid()
      }
    }),
  )
  step1.mount()
  let name_field = wform.field(step1_l().compose(step_name_l()))
  name_field.mount()
  let passed : RvCounter = { n: 0, }
  step1.handle_submit(
    on_group_submit=(_value, _meta) => passed.n = passed.n + 1,
    on_group_submit_invalid=() => (),
  )
  if passed.n != 0 || !name_field.meta().has_errors() {
    println("readme-verify FAIL: block4 gate/distribution")
    return
  }
  name_field.set_value("ok")
  step1.handle_submit(
    on_group_submit=(_value, _meta) => passed.n = passed.n + 1,
    on_group_submit_invalid=() => (),
  )
  if passed.n != 1 || wform.submission_attempts() != 0 {
    println("readme-verify FAIL: block4 group submit semantics")
    return
  }
  // ---- schema 组校验器 (block 5; ToJson is required, as documented) ----
  let step_schema = @builder.object({ "name": @builder.string().min_len(2) }).compile() catch {
    _ => abort("schema compile failed")
  }
  let sform = @core.FormApi::make({ step1: { name: "", }, })
  let sgroup = sform.group(
    step1_l(),
    on_submit_validate=@formSchema.schema_group_validator(step_schema),
  )
  sgroup.mount()
  let sname = sform.field(step1_l().compose(step_name_l()))
  sname.mount()
  sgroup.handle_submit()
  if !sname.meta().has_errors() {
    println("readme-verify FAIL: block5 schema distribution")
    return
  }
  println("readme-verify: all 5 blocks ok")
}
