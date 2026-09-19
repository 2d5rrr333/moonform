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
fn nickname_l() -> Lens[Profile, String] {
  field("nickname", p => p.nickname, (p, n) => { ..p, nickname: n, })
}

///|
fn age_l() -> Lens[Profile, Int] {
  field("age", p => p.age, (p, a) => { ..p, age: a, })
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
struct Outer {
  inner : Inner
} derive(Eq, Debug)

///|
test "doc: composed key derives from both segments" {
  fn inner_l() -> Lens[Outer, Inner] {
    field("inner", o => o.inner, (_o, i) => { inner: i, })
  }
  fn city_l() -> Lens[Inner, String] {
    field("city", i => i.city, (_i, c) => { city: c, })
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
fn login_email_l() -> Lens[Login, String] {
  field("email", l => l.email, (l, e) => { ..l, email: e, })
}

///|
test "doc: form lifecycle" {
  let form = FormApi::make({ email: "", password: "", })
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
fn username_l() -> Lens[Signup, String] {
  field("username", s => s.username, (_s, u) => { username: u, })
}

///|
test "doc: onChange validation fills the error slot" {
  let form = FormApi::make({ username: "", })
  let username = form.field(
    username_l(),
    on_change_validate=validator(v => {
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
struct Roster {
  friends : Array[Friend]
} derive(Eq, Debug)

///|
fn friends_l() -> Lens[Roster, Array[Friend]] {
  field("friends", r => r.friends, (_r, xs) => { friends: xs, })
}

///|
fn friend_name_l() -> Lens[Friend, String] {
  field("name", f => f.name, (_f, n) => { name: n, })
}

///|
test "doc: remove migrates meta to shifted slots" {
  let form = FormApi::make({
    friends: [{ name: "alice", }, { name: "bob", }, { name: "carol", }],
  })
  // mount a field for friends[1].name so the accessor is used
  let bob_name = form.field(at(friends_l(), 1).compose(friend_name_l()))
  bob_name.mount()
  // an error sits on friends[1].name
  form
  .meta_store()
  .update(friends_l().key.push_idx(1).push_field("name"), m => {
    m.with_cause_errors(ValidationCause::change(), Some(["taken"]))
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
fn token_l() -> Lens[AsyncForm, String] {
  field("token", f => f.token, (_f, t) => { token: t, })
}

///|
test "doc: debounced async validation on the virtual clock" {
  let vc = VirtualClock::make()
  let form = FormApi::make({ token: "", }).with_clock(vc.clock())
  let token = form.field(
    token_l(),
    on_change_async_debounce_ms=500,
    on_change_async_validate=async_validator((value, clock, done) => {
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

## Submit orchestration

```mbt check
///|
struct Order {
  qty : Int
} derive(Eq, Debug)

///|
struct SubmitCounter {
  mut n : Int
}

///|
fn qty_l() -> Lens[Order, Int] {
  field("qty", o => o.qty, (_o, q) => { qty: q, })
}

///|
test "doc: submit gates on validation" {
  let form = FormApi::make({ qty: 0, })
  let qty = form.field(
    qty_l(),
    on_submit_validate=validator(v => {
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
    ..SubmitOptions::make(),
    on_submit: Some(
      submit_handler((_v, done) => {
        submitted.n = submitted.n + 1
        done(SubmitResult::ok())
      }),
    ),
  })
  inspect(submitted.n, content="0") // blocked: onSubmit never ran
  qty.set_value(2)
  form.handle_submit() // no handler in this call: no-op success submit
  inspect(form.is_submitted(), content="true")
}
```
