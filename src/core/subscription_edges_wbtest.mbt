// Subscription blind-spot audit: mid-notify mutations on the notify_all /
// batch-flush paths, mid-notify subscribes, prefix-path liveness, mixed
// batch pending, and the flush-write immediacy contract.

// ---------------------------------------------------------------------------
// notify_all (reset / update): mid-notify unsubscribes
// ---------------------------------------------------------------------------

///|
test "notify_all: mid-notify unsubscribe honored (reset path)" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let a_hits = { n: 0, }
  let b_hits = { n: 0, }
  let b_cell = { n: 0, } // captures b's id once subscribed
  let _a = form.subscribe(() => {
    a_hits.n = a_hits.n + 1
    // the first callback unsubscribes the second subscriber mid-notify
    if b_cell.n == 0 {
      form.unsubscribe(2) // b subscribed second: id 2
      b_cell.n = 1
    }
  })
  let _b = form.subscribe(() => b_hits.n = b_hits.n + 1)
  form.reset() // notify_all
  assert_eq(a_hits.n, 1)
  assert_eq(b_hits.n, 0) // unsubscribed before its snapshot slot ran
}

// ---------------------------------------------------------------------------
// batch flush: mid-flush unsubscribes + mixed pending + flush writes
// ---------------------------------------------------------------------------

///|
test "batch flush: a callback unsubscribing a later subscriber is honored" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let a_hits = { n: 0, }
  let b_hits = { n: 0, }
  let _a = form.subscribe(() => {
    a_hits.n = a_hits.n + 1
    if a_hits.n == 1 {
      form.unsubscribe(2) // b subscribed second: id 2
    }
  })
  let _b = form.subscribe(() => b_hits.n = b_hits.n + 1)
  form.batch(() => {
    form.set_value(name_l(), "x")
    form.set_value(surname_l(), "y")
  })
  // the flush fires each subscriber at most once; b was unsubscribed by
  // a's flush callback before its own slot ran
  assert_eq(a_hits.n, 1)
  assert_eq(b_hits.n, 0)
}

///|
test "batch: notify and notify_all pending coexist (one fire per subscriber)" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let form_hits = { n: 0, }
  let name_hits = { n: 0, }
  let _a = form.subscribe(() => form_hits.n = form_hits.n + 1)
  let _b = form.subscribe_field(name_l().key, () => {
    name_hits.n = name_hits.n + 1
  })
  form.batch(() => {
    form.set_value(name_l(), "x") // pending (name, Value)
    form.reset() // pending_all
  })
  // the form-level subscriber fires once (pending_all), the name-field
  // subscriber once (pending match) — never twice
  assert_eq(form_hits.n, 1)
  assert_eq(name_hits.n, 1)
}

///|
test "batch flush: writes inside a flush callback notify immediately" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let form_hits = { n: 0, }
  let surname_hits = { n: 0, }
  let _s = form.subscribe_field(surname_l().key, () => {
    surname_hits.n = surname_hits.n + 1
  })
  let _f = form.subscribe(() => {
    form_hits.n = form_hits.n + 1
    // a flush callback writes OUTSIDE the batch body: batch depth is
    // already zero, so the write notifies immediately (documented
    // semantics — not coalesced into the finished batch)
    if form_hits.n == 1 {
      form.set_value(surname_l(), "from-flush")
    }
  })
  form.batch(() => form.set_value(name_l(), "x"))
  // the surname write landed through its own immediate notify
  assert_eq(surname_hits.n, 1)
  assert_eq(form.get_value(surname_l()), "from-flush")
  // the form-level subscriber saw both events: the flush + the flush-time
  // write's immediate notify
  assert_eq(form_hits.n, 2)
}

// ---------------------------------------------------------------------------
// mid-notify subscribes: outside the snapshot, no in-flight event
// ---------------------------------------------------------------------------

///|
test "notify: a subscription added mid-notify receives no in-flight event" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let late_hits = { n: 0, }
  let cell = { n: 0, }
  let _first = form.subscribe_field(name_l().key, () => {
    if cell.n == 0 {
      cell.n = 1
      let _late = form.subscribe_field(name_l().key, () => {
        late_hits.n = late_hits.n + 1
      })
    }
  })
  form.set_value(name_l(), "x") // the new subscription is outside the snapshot
  assert_eq(late_hits.n, 0)
  form.set_value(name_l(), "y") // the next event reaches it
  assert_eq(late_hits.n, 1)
}

// ---------------------------------------------------------------------------
// prefix-path liveness: unsubscribe of an under-subscriber mid-notify
// ---------------------------------------------------------------------------

///|
test "notify: under-subscriber unsubscribed mid-notify does not fire" {
  let form = FormApi::make({ user: { first: "", last: "", }, other: "", })
  let under_hits = { n: 0, }
  let cell = { n: 0, }
  let user_l : Lens[SubOuter, SubNested] = field("user", o => o.user, (o, u) => {
    ..o,
    user: u,
  })
  let _field_sub = form.subscribe_field(sub_user_first_l().key, () => {
    if cell.n == 0 {
      cell.n = 1
      form.unsubscribe(2) // the under-subscriber subscribed second
    }
  })
  let _under_sub = form.subscribe_under(user_l.key, () => {
    under_hits.n = under_hits.n + 1
  })
  // the write to user.first matches BOTH subscribers; the field subscriber
  // (first in the snapshot) unsubscribes the under-subscriber before its
  // slot runs
  form.set_value(sub_user_first_l(), "a")
  assert_eq(under_hits.n, 0)
  form.set_value(sub_user_last_l(), "b")
  assert_eq(under_hits.n, 0) // still gone
}

// ---------------------------------------------------------------------------
// self-unsubscribing subscriber: fires exactly once, ever
// ---------------------------------------------------------------------------

///|
test "notify: a self-unsubscribing subscriber fires exactly once" {
  let form = FormApi::make({ name: "a", surname: "", age: 0, })
  let hits = { n: 0, }
  let id_cell = { n: 0, } // the subscribe handle, filled once available
  let id = form.subscribe(() => {
    hits.n = hits.n + 1
    form.unsubscribe(id_cell.n)
  })
  id_cell.n = id
  form.set_value(name_l(), "a1")
  form.set_value(surname_l(), "b1")
  form.set_value(name_l(), "a2")
  assert_eq(hits.n, 1)
}
