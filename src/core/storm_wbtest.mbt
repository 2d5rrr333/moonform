// Reentrancy and notification-storm audits: the paths React apps actually
// hit — listeners mutating state during dispatch, unsubscribing mid-notify,
// nested batches, submit re-entered from a change listener.

///|
struct Storm {
  sname : String
  sage : Int
} derive(Eq, Debug)

///|
pub extend Storm with Debug::{to_repr}

///|
pub extend Storm with Eq::{not_equal, equal}

///|
fn storm_name_l() -> Lens[Storm, String] {
  field("name", (s : Storm) => s.sname, (s, n) => { ..s, sname: n, })
}

///|
fn storm_age_l() -> Lens[Storm, Int] {
  field("age", (s : Storm) => s.sage, (s, a) => { ..s, sage: a, })
}

///|
test "storm: unsubscribe during notify does not break remaining subscribers" {
  let form = FormApi::make({ sname: "", sage: 0, })
  let hits_a = { n: 0, }
  let hits_b = { n: 0, }
  let hits_c = { n: 0, }
  // A (first) unsubscribes itself and B (second) while being notified; C
  // (third) must still fire for the SAME notification — removals must take
  // effect immediately without breaking the in-flight dispatch.
  let sub_a = { id: 0, }
  let sub_b = { id: 0, }
  sub_a.id = form.subscribe_field(storm_name_l().key, () => {
    hits_a.n = hits_a.n + 1
    // mid-notify unsubscribe of self and a LATER subscriber
    form.unsubscribe(sub_a.id)
    form.unsubscribe(sub_b.id)
  })
  sub_b.id = form.subscribe_field(storm_name_l().key, () => {
    hits_b.n = hits_b.n + 1
  })
  let _c = form.subscribe_field(storm_name_l().key, () => {
    hits_c.n = hits_c.n + 1
  })
  form.set_value(storm_name_l(), "x")
  assert_eq(hits_a.n, 1) // A fired, then removed itself
  assert_eq(hits_b.n, 0) // B removed before its turn in the same dispatch
  assert_eq(hits_c.n, 1) // C unaffected — removal kept the dispatch sound
  // a later notification reaches only C
  form.set_value(storm_name_l(), "y")
  assert_eq(hits_a.n, 1)
  assert_eq(hits_b.n, 0)
  assert_eq(hits_c.n, 2)
}

///|
struct SubIdCell {
  mut id : Int
}

///|
test "storm: listener writing another field during its own notification" {
  // a change listener that cascades a write into a DIFFERENT field —
  // the nested set_value dispatches recursively; no infinite loop because
  // the cascade target's listener does not write back
  let form = FormApi::make({ sname: "", sage: 0, })
  let cascade_seen = { n: 0, }
  let name = form.field(storm_name_l(), on_change=_v => {
    cascade_seen.n = cascade_seen.n + 1
    // cascade: name changes imply age resets (a real cross-field pattern)
    if form.get_value(storm_age_l()) != 0 {
      form.set_value(storm_age_l(), 0)
    }
  })
  let _age = form.field(storm_age_l())
  name.mount()
  _age.mount()
  form.set_value(storm_age_l(), 42)
  form.set_value(storm_name_l(), "trigger")
  assert_eq(cascade_seen.n, 1)
  assert_eq(form.get_value(storm_age_l()), 0) // cascade applied
  assert_eq(form.get_value(storm_name_l()), "trigger")
}

///|
test "storm: nested batches flush exactly once at the outermost level" {
  let form = FormApi::make({ sname: "", sage: 0, })
  let hits = { n: 0, }
  let _sub = form.subscribe(() => hits.n = hits.n + 1)
  // batch opened by a listener INSIDE another batch (an adapter pattern:
  // bridge refresh coalesces inside the form's own batch)
  form.batch(() => {
    form.set_value(storm_name_l(), "a")
    form.batch(() => {
      form.set_value(storm_age_l(), 1)
      form.batch(() => form.set_value(storm_name_l(), "b"))
    })
    form.batch(() => form.set_value(storm_age_l(), 2))
  })
  assert_eq(hits.n, 1) // single flush at the outermost level
  assert_eq(form.get_value(storm_name_l()), "b")
  assert_eq(form.get_value(storm_age_l()), 2)
}

///|
test "storm: batch flushed by an inner listener's writes stays coalesced" {
  // a listener firing DURING a batch performs further writes — those must
  // land in the SAME batch (already open), not trigger early flushes
  let form = FormApi::make({ sname: "", sage: 0, })
  let hits = { n: 0, }
  let _sub = form.subscribe(() => hits.n = hits.n + 1)
  let name = form.field(storm_name_l(), on_change=_v => {
    // write from inside dispatch (inside the batch)
    if form.get_value(storm_age_l()) == 0 {
      form.set_value(storm_age_l(), 99)
    }
  })
  name.mount()
  let hits_after_mount = hits.n // mount notifies meta once (subscribed before)
  form.batch(() => {
    form.set_value(storm_name_l(), "x")
    // the listener's nested write happened above; outer batch continues
    form.set_value(storm_name_l(), "y")
  })
  // the whole cascade (two name writes + the cascaded age write) flushed ONCE
  assert_eq(hits.n, hits_after_mount + 1)
  assert_eq(form.get_value(storm_age_l()), 99)
}

///|
test "storm: submit re-entered from a change listener is bounded" {
  // pathological: an on_change listener triggers a submit (which writes
  // touched flags and notifies) — must not recurse into the listener again
  let form = FormApi::make({ sname: "ok", sage: 0, })
  let submits = { n: 0, }
  let listener_runs = { n: 0, }
  let name = form.field(storm_name_l(), on_change=_v => {
    listener_runs.n = listener_runs.n + 1
    // guard: only submit once ever
    if submits.n == 0 {
      submits.n = submits.n + 1
      form.handle_submit()
    }
  })
  name.mount()
  form.set_value(storm_name_l(), "trigger")
  assert_eq(listener_runs.n, 1) // no re-entry
  assert_eq(submits.n, 1)
  assert_true(form.is_submitted()) // the nested submit completed
}
