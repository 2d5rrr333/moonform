// real_clock: the js host adapter for the core Clock protocol — real
// timers behind the same injectable protocol the VirtualClock drives in
// tests (documented deviation D-P7: the core stays timer-free; hosts
// bridge real async). Debounce/race-abort/async-submit all work
// identically against either clock.

///|
extern "js" fn js_now_ms() -> Int =
  #| () => Date.now()

///|
extern "js" fn js_set_timeout(delay_ms : Int, cb : () -> Unit) -> Int =
  #| (delay, cb) => globalThis.setTimeout(() => cb(), delay)

///|
extern "js" fn js_clear_timeout(id : Int) -> Unit =
  #| (id) => globalThis.clearTimeout(id)

///|
/// A Clock over real host timers (js target): `now` is wall-clock ms,
/// `schedule` is setTimeout, `cancel` is clearTimeout. Attach with
/// `FormApi::with_clock(real_clock())` to run debounced async validation
/// and asynchronous submissions against real time — the same protocol the
/// VirtualClock drives deterministically in tests.
pub fn real_clock() -> @core.Clock {
  @core.Clock::make(js_now_ms, (delay, cb) => js_set_timeout(delay, cb), id => {
    js_clear_timeout(id)
  })
}
