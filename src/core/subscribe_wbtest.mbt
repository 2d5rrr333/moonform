// Subscriptions + field listeners (translated from FieldApi.spec listener
// tests and the form-state subscription scenarios).

///|
struct StrCell {
  mut v : String?
}

///|
fn StrCell::make() -> StrCell {
  { v: None, }
}

///|
struct Count {
  mut n : Int
}

// upstream: "should run listener onChange"

///|
test "listener: onChange runs with the new value" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let cell = StrCell::make()
  let field = form.field(name_l(), on_change=value => cell.v = Some(value))
  field.mount()
  field.set_value("other")
  assert_eq(cell.v, Some("other"))
}

// upstream: "should not run the listener onChange on mount"

///|
test "listener: onChange does not run on mount" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let cell = StrCell::make()
  let field = form.field(name_l(), on_change=value => cell.v = Some(value))
  field.mount()
  assert_eq(cell.v, None)
}

// upstream: "should change the form state when running listener onChange"

///|
test "listener: onChange can change other form state" {
  let form = FormApi::make({ name: "foo", surname: "bar", age: 0, })
  let greet_l = surname_l()
  let field = form.field(name_l(), on_change=value => {
    form.set_value(greet_l, "hello \{value}")
  })
  field.mount()
  field.set_value("baz")
  assert_eq(form.get_value(name_l()), "baz")
  assert_eq(form.get_value(surname_l()), "hello baz")
}

// upstream: "should run listener onBlur"

///|
test "listener: onBlur runs on handle_blur" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let field = form.field(name_l(), on_blur=() => count.n = count.n + 1)
  field.mount()
  field.handle_blur()
  assert_eq(count.n, 1)
  // blur also marks the field touched + blurred
  let m = field.meta()
  assert_true(m.is_touched)
  assert_true(m.is_blurred)
}

// upstream: "should run listener onMount"

///|
test "listener: onMount runs at mount" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let field = form.field(name_l(), on_mount=() => count.n = count.n + 1)
  field.mount()
  assert_eq(count.n, 1)
}

// upstream: "should run listener onUnmount"

///|
test "listener: onUnmount runs at unmount" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let field = form.field(name_l(), on_unmount=() => count.n = count.n + 1)
  field.mount()
  assert_eq(count.n, 0)
  field.unmount()
  assert_eq(count.n, 1)
}

// upstream: "should reset the form on a listener"

///|
test "listener: onChange can reset the form" {
  let form = FormApi::make({ name: "foo", surname: "bar", age: 0, })
  let field = form.field(name_l(), on_change=_ => {
    let reset_to : Person = { ..form.values(), surname: "", }
    form.reset(values=reset_to)
  })
  field.mount()
  field.set_value("other")
  assert_eq(form.get_value(name_l()), "other")
  assert_eq(form.get_value(surname_l()), "")
}

///|
test "listener: dont_run_listeners skips the onChange listener" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let cell = StrCell::make()
  let field = form.field(name_l(), on_change=value => cell.v = Some(value))
  field.mount()
  field.set_value("other", dont_run_listeners=true)
  assert_eq(cell.v, None)
  assert_eq(form.get_value(name_l()), "other") // value still written
}

// ---------------------------------------------------------------------------
// subscriptions (form-state spec scenarios)
// ---------------------------------------------------------------------------

///|
test "subscription: value change notifies, subscriber reads new value" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let seen = StrCell::make()
  let _id = form.subscribe_field(name_l().key, () => {
    seen.v = Some(form.get_value(name_l()))
  })
  form.set_value(name_l(), "other")
  assert_eq(seen.v, Some("other"))
}

///|
test "subscription: kind filter ignores unrelated change kinds" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let field = form.field(name_l())
  field.mount()
  let _id = form.subscribe_field(name_l().key, kinds=[Value], () => {
    count.n = count.n + 1
  })
  field.handle_blur() // touched/blurred: Meta kind — must not fire
  assert_eq(count.n, 0)
  field.set_value("other") // Value kind — fires
  assert_eq(count.n, 1)
}

///|
test "subscription: field subscriber not notified for sibling fields" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let _id = form.subscribe_field(name_l().key, () => count.n = count.n + 1)
  form.set_value(surname_l(), "x")
  assert_eq(count.n, 0)
  form.set_value(name_l(), "y")
  assert_eq(count.n, 1)
}

///|
test "subscription: form-level subscriber hears any change" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let _id = form.subscribe(() => count.n = count.n + 1)
  form.set_value(name_l(), "a")
  form.set_value(surname_l(), "b")
  assert_eq(count.n, 2)
}

///|
test "subscription: unsubscribe stops notifications (stable handle)" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let id = form.subscribe(() => count.n = count.n + 1)
  form.set_value(name_l(), "a")
  assert_eq(count.n, 1)
  form.unsubscribe(id)
  form.set_value(name_l(), "b")
  assert_eq(count.n, 1) // no further notifications
}

///|
test "subscription: batch coalesces multiple writes into one notification" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let seen = StrCell::make()
  let _id = form.subscribe_field(name_l().key, () => {
    count.n = count.n + 1
    seen.v = Some(form.get_value(name_l()))
  })
  form.batch(() => {
    form.set_value(name_l(), "a")
    form.set_value(name_l(), "ab")
    form.set_value(name_l(), "abc")
  })
  assert_eq(count.n, 1) // one notification for the whole batch
  assert_eq(seen.v, Some("abc")) // reading the final value
}

///|
test "subscription: nested batches flush once at the outermost level" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let count = { n: 0, }
  let _id = form.subscribe(() => count.n = count.n + 1)
  form.batch(() => {
    form.set_value(name_l(), "a")
    form.batch(() => form.set_value(surname_l(), "b"))
  })
  assert_eq(count.n, 1)
}

///|
test "subscription: reset notifies every subscriber" {
  let form = FormApi::make({ name: "test", surname: "", age: 0, })
  let form_hits = { n: 0, }
  let field_hits = { n: 0, }
  let _a = form.subscribe(() => form_hits.n = form_hits.n + 1)
  let _b = form.subscribe_field(name_l().key, () => {
    field_hits.n = field_hits.n + 1
  })
  form.reset()
  assert_eq(form_hits.n, 1)
  assert_eq(field_hits.n, 1)
}

// -- prefix (subtree) subscriptions --------------------------------------------------

///|
struct SubNested {
  first : String
  last : String
} derive(Eq, Debug)

///|
struct SubOuter {
  user : SubNested
  other : String
} derive(Eq, Debug)

///|
fn sub_user_first_l() -> Lens[SubOuter, String] {
  field("user", (o : SubOuter) => o.user, (o, u) => { ..o, user: u, }).compose(
    field("first", (n : SubNested) => n.first, (n, f) => { ..n, first: f, }),
  )
}

///|
fn sub_user_last_l() -> Lens[SubOuter, String] {
  field("user", (o : SubOuter) => o.user, (o, u) => { ..o, user: u, }).compose(
    field("last", (n : SubNested) => n.last, (n, l) => { ..n, last: l, }),
  )
}

///|
fn sub_other_l() -> Lens[SubOuter, String] {
  field("other", o => o.other, (o, s) => { ..o, other: s, })
}

///|
test "subscription: subscribe_under fires on the prefix key and every child" {
  let form = FormApi::make({ user: { first: "", last: "", }, other: "", })
  let hits = { n: 0, }
  let _id = form.subscribe_under(Key::field("user"), () => hits.n = hits.n + 1)
  form.set_value(sub_user_first_l(), "a") // child of the prefix
  assert_eq(hits.n, 1)
  form.set_value(sub_user_last_l(), "b") // another child
  assert_eq(hits.n, 2)
  form.set_value(sub_other_l(), "x") // outside the prefix
  assert_eq(hits.n, 2)
}

///|
test "subscription: subscribe_under covers the prefix key itself" {
  let form = FormApi::make({ user: { first: "", last: "", }, other: "", })
  let hits = { n: 0, }
  let user_l : Lens[SubOuter, SubNested] = field("user", o => o.user, (o, u) => {
    ..o,
    user: u,
  })
  let _id = form.subscribe_under(user_l.key, () => hits.n = hits.n + 1)
  form.set_value(user_l, { first: "a", last: "b", }) // the prefix key itself
  assert_eq(hits.n, 1)
}

///|
test "subscription: subscribe_under respects change-kind filters" {
  let form = FormApi::make({ user: { first: "", last: "", }, other: "", })
  let value_hits = { n: 0, }
  let _id = form.subscribe_under(Key::field("user"), kinds=[Value], () => {
    value_hits.n = value_hits.n + 1
  })
  form.set_value(sub_user_first_l(), "a") // Value + Meta fires Value only
  assert_eq(value_hits.n, 1)
  form.blur_field(sub_user_first_l().key) // Meta only: filtered out
  assert_eq(value_hits.n, 1)
}

///|
test "subscription: unsubscribe stops prefix notifications" {
  let form = FormApi::make({ user: { first: "", last: "", }, other: "", })
  let hits = { n: 0, }
  let id = form.subscribe_under(Key::field("user"), () => hits.n = hits.n + 1)
  form.set_value(sub_user_first_l(), "a")
  assert_eq(hits.n, 1)
  form.unsubscribe(id)
  form.set_value(sub_user_first_l(), "b")
  assert_eq(hits.n, 1) // no further notifications
}
