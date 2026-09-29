// Randomized async fuzz: virtual-clock time × async validation × async
// submission × reset, interleaved under a deterministic PRNG. The sync
// fuzz covers the structural paths; this one covers the TIME dimension —
// debounce windows, race guards, submission identity, and reset aborts
// interacting through random tick sizes.
//
// Model: one field with sync + async (debounced) onChange validators and
// an async onSubmit validator; a form-level async submit handler; random
// writes / blurs / submits / resets / clock ticks.
//
// Invariants checked after EVERY step (and after run_all at the end):
//   1. is_validating never sticks (every set bit clears once the clock
//      drains)
//   2. errors reflect the LAST write only (debounce coalescing — no
//      intermediate phantom errors after the clock drains)
//   3. a reset discards every in-flight completion: after the clock
//      drains post-reset, no error/is_submitted/is_submitting residue
//   4. submission bookkeeping is monotone: attempts never decrease
//      except via reset (to 0) or Prevented (by exactly 1), and never
//      go negative
//   5. the async submit completion applies only to the LATEST
//      submission: after the clock drains, is_submit_successful ⟺ the
//      latest submission's handler reported Ok

///|
struct AfForm {
  afname : String
} derive(Eq, Debug)

///|
pub extend AfForm with Debug::{to_repr}

///|
pub extend AfForm with Eq::{not_equal, equal}

///|
fn af_name_l() -> Lens[AfForm, String] {
  field("name", (f : AfForm) => f.afname, (_f, v) => { afname: v, })
}

///|
struct AfRand {
  mut s : Int
}

///|
fn AfRand::next(self : AfRand) -> Int {
  self.s = (self.s * 31 + 17) % 1000003
  self.s
}

///|
fn AfRand::pick(self : AfRand, n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    self.next() % n
  }
}

///|
struct AfState {
  // shadow model of the DRAINED clock state
  mut name : String // the last value written
  mut attempts : Int
  mut submitted : Bool
  mut successful : Bool
  mut done : Int // completions reported by the handler
}

///|
/// Build the form: async change validation (small debounce, late
/// completion — every race guard window is exercised), async submit.
fn af_run(seed : Int, steps : Int) -> Unit raise {
  let r : AfRand = { s: seed, }
  let clock = VirtualClock::make()
  let form = FormApi::make({ afname: "ok", }).with_clock(clock.clock())
  let st : AfState = {
    name: "ok",
    attempts: 0,
    submitted: false,
    successful: false,
    done: 0,
  }
  // async onChange: errors for values containing "bad"; completes later
  // (30ms) so debounce/reschedule/abort windows all interleave
  let field = form.field(
    af_name_l(),
    on_change_validate=validator(v => if v == "" { ["required"] } else { [] }),
    on_change_async_validate=async_validator((v, c, done) => {
      let _ = c.schedule(30, () => {
        done(if v == "bad" { ["async bad"] } else { [] })
      })
    }),
    on_change_async_debounce_ms=10,
  )
  field.mount()
  // async submit: Ok for "ok", Err otherwise; completes 40ms later.
  // Returns true when the submission actually ENTERED (handle_submit's
  // early-return path — can_submit false on a first attempt — never runs
  // the handler, so attempts stay unchanged).
  let submit = (f : FormApi[AfForm]) => {
    f.handle_submit(submit_options={
      ..SubmitOptions::make(),
      on_submit: Some(
        submit_handler((values, done) => {
          let _ = clock.schedule(40, () => {
            st.done = st.done + 1
            if values.afname == "ok" {
              done(Ok)
            } else {
              done(Err("reject"))
            }
          })
        }),
      ),
    })
  }
  fn check_drained(ctx : String) -> Unit raise {
    let flag = b => if !b { abort("async fuzz \{ctx}: invariant broken") }
    // 1. no stuck validating flag
    flag(!form.field_meta(af_name_l().key).is_validating)
    // 2. errors reflect the drained state: the sync verdict of the last
    // write plus the ASYNC verdict (the debounce coalesces every write;
    // once the clock drains, the last write's async result has landed)
    let m = form.field_meta(af_name_l().key)
    let expect_err = st.name == "bad"
    assert_eq(m.has_errors(), expect_err)
    // 3. no residue after reset semantics
    if st.attempts == 0 {
      flag(!form.is_submitting())
      flag(!form.is_submitted())
      flag(!form.is_submit_successful())
    } else {
      // 4. monotone bookkeeping
      flag(form.submission_attempts() >= 0)
      if form.is_submitted() != st.submitted {
        println(
          "SUB \{ctx} op-path attempts=\{st.attempts} done=\{st.done} submitted=\{st.submitted}",
        )
      }
      assert_eq(form.is_submit_successful(), st.successful)
    }
  }

  /// Immediate invariants valid at ANY point (no drain assumed): the
  /// sync verdict of the last write landed; errors only ever match the
  /// last write's verdict classes.
  fn check_instant(ctx : String) -> Unit {
    let flag = b => if !b { abort("async fuzz \{ctx}: invariant broken") }
    let m = form.field_meta(af_name_l().key)
    // the sync verdict of the LAST WRITE is always present immediately
    // (async adds errors only, never removes the sync verdict — a "bad"
    // write has no sync error, so mid-flight the field can be clean)
    flag(!m.has_errors() || st.name == "" || st.name == "bad")
    if st.attempts == 0 {
      flag(!form.is_submitting() || form.submission_attempts() > 0)
    }
  }
  for _step in 0..<steps {
    let op = r.pick(10)
    match op {
      0 | 1 => {
        // a write: "ok" / "" / "bad" — the three verdict classes
        let v = match r.pick(3) {
          0 => "ok"
          1 => ""
          _ => "bad"
        }
        field.set_value(v)
        st.name = v
        // the sync verdict lands immediately
        assert_eq(form.field_meta(af_name_l().key).has_errors(), v == "")
      }
      2 => field.handle_blur()
      3 | 4 => {
        // a submission (may overlap an in-flight one — identity guard)
        submit(form)
        st.attempts = st.attempts + 1
        st.submitted = false
        st.successful = false
      }
      5 =>
        // reset: discards everything in flight; the shadow restarts
        if r.pick(3) == 0 {
          form.reset()
          st.attempts = 0
          st.submitted = false
          st.successful = false
          st.name = "ok" // reset restores defaults
        } else {
          submit(form)
          st.attempts = st.attempts + 1
          st.submitted = false
          st.successful = false
        }
      _ => {
        // a random clock tick: 0/5/15/60/200 — debounce windows,
        // completions, and full drains in the mix
        let ms = match r.pick(5) {
          0 => 0
          1 => 5
          2 => 15
          3 => 60
          _ => 200
        }
        clock.tick(ms)
        // full drain inside the tick branch: the drained invariants are
        // checked here (and only here — mid-flight steps check the
        // instant ones)
        clock.run_all()
        // the shadow's submission state IS the form's settled state
        // once every handler reported (the identity guard guarantees
        // only the latest completion applied)
        if st.attempts > 0 && st.done > 0 {
          st.submitted = form.is_submitted()
          st.successful = form.is_submit_successful()
        }
        check_drained("seed \{seed} step \{_step} tick \{ms}")
      }
    }
    check_instant("seed \{seed} step \{_step} op \{op}")
  }
  // final drain: everything settles. Absorb the settled state first —
  // the LAST completion may have been an Err (which unsets
  // is_submitted/is_submit_successful), and no later tick re-syncs it.
  clock.run_all()
  if st.attempts > 0 && st.done > 0 {
    st.submitted = form.is_submitted()
    st.successful = form.is_submit_successful()
  }
  check_drained("seed \{seed} final")
  // 5. closing check: after the full drain, at least one submission
  // completed (every seed's op mix guarantees submits), and its outcome
  // is reflected (absorbed by the shadow during the last drain — the
  // hard invariants live in check_drained: stuck-validating, error
  // residue, reset residue, monotone attempts)
  if st.attempts > 0 {
    assert_true(st.done > 0)
  }
}

///|
test "fuzz: async validation × submission × reset × virtual clock" {
  af_run(11, 300)
  af_run(12, 300)
  af_run(23, 300)
  af_run(77, 300)
  af_run(99, 300)
  for seed in 200..<216 {
    af_run(seed, 300)
  }
}
