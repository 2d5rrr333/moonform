# moonform core — README with doc tests

The `mbt check` blocks below are executed as tests by `moon test`
(documentation that cannot rot).

## Lens: define a field accessor

```mbt check
///|
struct Profile {
  nickname : String
  age : Int
} derive(Eq, Debug)

///|
pub extend Profile with Eq::{not_equal, equal}

///|
pub extend Profile with Debug::{to_repr}

///|
fn nickname_l() -> @core.Lens[Profile, String] {
  @core.field("nickname", p => p.nickname, (p, n) => { ..p, nickname: n, })
}

///|
fn age_l() -> @core.Lens[Profile, Int] {
  @core.field("age", p => p.age, (p, a) => { ..p, age: a, })
}

///|
test "doc: lens read/write" {
  let p : Profile = { nickname: "moon", age: 3, }
  inspect(
    nickname_l().get(p),
    content=(
      #|moon
    ),
  )
  let p2 = age_l().set(p, 4)
  inspect(p2.age, content="4")
  inspect(p.age, content="3") // value semantics: original untouched
}
```

## Composed keys

```mbt check
///|
struct Inner {
  city : String
} derive(Eq, Debug)

///|
pub extend Inner with Eq::{not_equal, equal}

///|
pub extend Inner with Debug::{to_repr}

///|
struct Outer {
  inner : Inner
} derive(Eq, Debug)

///|
pub extend Outer with Eq::{not_equal, equal}

///|
pub extend Outer with Debug::{to_repr}

///|
test "doc: composed key derives from both segments" {
  fn inner_l() -> @core.Lens[Outer, Inner] {
    @core.field("inner", o => o.inner, (_o, i) => { inner: i, })
  }
  fn city_l() -> @core.Lens[Inner, String] {
    @core.field("city", i => i.city, (_i, c) => { city: c, })
  }
  let o : Outer = { inner: { city: "hz", }, }
  let composed = inner_l().compose(city_l())
  inspect(composed.key.render(), content="inner.city")
  inspect(composed.get(o), content="hz")
}
```

## FormApi basics: values, dirty, reset

```mbt check
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
fn login_email_l() -> @core.Lens[Login, String] {
  @core.field("email", l => l.email, (l, e) => { ..l, email: e, })
}

///|
test "doc: form lifecycle" {
  let form = @core.FormApi::make({ email: "", password: "", })
  inspect(
    form.get_value(login_email_l()),
    content=(
      #|
    ),
  )
  form.set_value(login_email_l(), "a@b.c")
  inspect(form.is_dirty(), content="true")
  form.reset()
  inspect(
    form.get_value(login_email_l()),
    content=(
      #|
    ),
  )
  inspect(form.is_dirty(), content="false")
}
```

## Validation: onChange slot semantics

```mbt check
///|
struct Signup {
  username : String
} derive(Eq, Debug)

///|
pub extend Signup with Eq::{not_equal, equal}

///|
pub extend Signup with Debug::{to_repr}

///|
fn username_l() -> @core.Lens[Signup, String] {
  @core.field("username", s => s.username, (_s, u) => { username: u, })
}

///|
test "doc: onChange validation fills the error slot" {
  let form = @core.FormApi::make({ username: "", })
  let username = form.field(
    username_l(),
    on_change_validate=@core.validator(v => {
      if v.length() < 3 {
        ["min 3 chars"]
      } else {
        []
      }
    }),
  )
  username.mount()
  username.set_value("ab")
  let errs = username.meta().errors()
  inspect(errs.length(), content="1")
  inspect(errs[0], content="min 3 chars")
  username.set_value("abc")
  inspect(username.meta().errors().length(), content="0")
}
```

## Array fields with meta migration

```mbt check
///|
struct Friend {
  name : String
} derive(Eq, Debug)

///|
pub extend Friend with Eq::{not_equal, equal}

///|
pub extend Friend with Debug::{to_repr}

///|
struct Roster {
  friends : Array[Friend]
} derive(Eq, Debug)

///|
pub extend Roster with Eq::{not_equal, equal}

///|
pub extend Roster with Debug::{to_repr}

///|
fn friends_l() -> @core.Lens[Roster, Array[Friend]] {
  @core.field("friends", r => r.friends, (_r, xs) => { friends: xs, })
}

///|
fn friend_name_l() -> @core.Lens[Friend, String] {
  @core.field("name", f => f.name, (_f, n) => { name: n, })
}

///|
test "doc: remove migrates meta to shifted slots" {
  let form = @core.FormApi::make({
    friends: [{ name: "alice", }, { name: "bob", }, { name: "carol", }],
  })
  // mount a field for friends[1].name so the accessor is used
  let bob_name = form.field(@core.at(friends_l(), 1).compose(friend_name_l()))
  bob_name.mount()
  // an error sits on friends[1].name
  form
  .meta_store()
  .update(friends_l().key.push_idx(1).push_field("name"), m => {
    m.with_cause_errors(@core.ValidationCause::change(), Some(["taken"]))
  })
  form.remove_value(friends_l(), 0)
  // the error followed the element: now at friends[0].name
  let moved = friends_l().key.push_idx(0).push_field("name")
  let errs = form.field_meta(moved).errors()
  inspect(errs.length(), content="1")
  inspect(errs[0], content="taken")
}
```

## Virtual clock: async validation, deterministically

```mbt check
///|
struct AsyncForm {
  token : String
} derive(Eq, Debug)

///|
pub extend AsyncForm with Eq::{not_equal, equal}

///|
pub extend AsyncForm with Debug::{to_repr}

///|
fn token_l() -> @core.Lens[AsyncForm, String] {
  @core.field("token", f => f.token, (_f, t) => { token: t, })
}

///|
test "doc: debounced async validation on the virtual clock" {
  let vc = @core.VirtualClock::make()
  let form = @core.FormApi::make({ token: "", }).with_clock(vc.clock())
  let token = form.field(
    token_l(),
    on_change_async_debounce_ms=500,
    on_change_async_validate=@core.async_validator((value, clock, done) => {
      let _ = clock.schedule(100, () => {
        if value == "taken" {
          done(["token already taken"])
        } else {
          done([])
        }
      })
    }),
  )
  token.mount()
  token.set_value("taken")
  token.set_value("taken") // second keystroke inside the window
  vc.run_all() // one tick past window + validator sleep
  let errs = token.meta().errors()
  inspect(errs.length(), content="1")
  inspect(errs[0], content="token already taken")
}
```

## Field groups: group validation, distribution, group submit

```mbt check
///|
struct Wiz {
  step1 : WizStep
  step2 : WizStep
} derive(Eq, Debug)

///|
pub extend Wiz with Eq::{not_equal, equal}

///|
pub extend Wiz with Debug::{to_repr}

///|
struct WizStep {
  title : String
} derive(Eq, Debug)

///|
pub extend WizStep with Eq::{not_equal, equal}

///|
pub extend WizStep with Debug::{to_repr}

///|
fn wiz_step1_l() -> @core.Lens[Wiz, WizStep] {
  @core.field("step1", w => w.step1, (w, s) => { ..w, step1: s, })
}

///|
fn wiz_title_l() -> @core.Lens[WizStep, String] {
  @core.field("title", s => s.title, (_s, t) => { title: t, })
}

///|
test "doc: group validator distributes field errors; group submit is form-safe" {
  let form = @core.FormApi::make({
    step1: { title: "", },
    step2: { title: "ok", },
  })
  let step1 = form.group(
    wiz_step1_l(),
    on_submit_validate=@core.group_validator_value(g => {
      if g.title == "" {
        @core.GroupValidationResult::group_and_fields("Step incomplete", [
          (@core.Key::field("title"), "Title is required"),
        ])
      } else {
        @core.GroupValidationResult::valid()
      }
    }),
  )
  let title = form.field(wiz_step1_l().compose(wiz_title_l()))
  step1.mount()
  title.mount()
  let submitted : SubmitCounter = { n: 0, }
  step1.handle_submit(
    on_group_submit=(_v, _meta) => submitted.n = submitted.n + 1,
    on_group_submit_invalid=() => (),
  )
  inspect(submitted.n, content="0") // blocked
  inspect(step1.errors().length(), content="1") // group-level error
  inspect(
    title.meta().errors()[0],
    content="Title is required", // distributed to the child field
  )
  inspect(form.submission_attempts(), content="0") // the form never submitted
  title.set_value("done")
  step1.handle_submit(
    on_group_submit=(_v, _meta) => submitted.n = submitted.n + 1,
    on_group_submit_invalid=() => (),
  )
  inspect(submitted.n, content="1") // re-validated and passed
  inspect(step1.errors().length(), content="0")
}
```

## Submit orchestration

```mbt check
///|
struct Order {
  qty : Int
} derive(Eq, Debug)

///|
pub extend Order with Eq::{not_equal, equal}

///|
pub extend Order with Debug::{to_repr}

///|
struct SubmitCounter {
  mut n : Int
}

///|
fn qty_l() -> @core.Lens[Order, Int] {
  @core.field("qty", o => o.qty, (_o, q) => { qty: q, })
}

///|
test "doc: submit gates on validation" {
  let form = @core.FormApi::make({ qty: 0, })
  let qty = form.field(
    qty_l(),
    on_submit_validate=@core.validator(v => {
      if v < 1 {
        ["qty must be >= 1"]
      } else {
        []
      }
    }),
  )
  qty.mount()
  let submitted : SubmitCounter = { n: 0, }
  form.handle_submit(submit_options={
    ..@core.SubmitOptions::make(),
    on_submit: Some(
      @core.submit_handler((_v, done) => {
        submitted.n = submitted.n + 1
        done(@core.SubmitResult::ok())
      }),
    ),
  })
  inspect(submitted.n, content="0") // blocked: onSubmit never ran
  qty.set_value(2)
  form.handle_submit() // no handler in this call: no-op success submit
  inspect(form.is_submitted(), content="true")
}
```
