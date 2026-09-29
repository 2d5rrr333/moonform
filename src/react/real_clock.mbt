// real_clock: the js host adapter for the core Clock protocol — real
// timers behind the same injectable protocol the VirtualClock drives in
// tests (documented deviation D-P7: the core stays timer-free; hosts
// bridge real async). Debounce/race-abort/async-submit all work
// identically against either clock.

///|
/// Wall-clock seconds since the epoch (fits MoonBit's 32-bit Int until
/// 2038; the core never reads `now` — it exists for host diagnostics.
/// `Date.now()` milliseconds would silently overflow Int).
extern "js" fn js_now_secs() -> Int =
  #| () => Math.floor(Date.now() / 1000)

///|
/// setTimeout behind a numeric-id registry: browsers return numeric ids
/// but Node/Bun return Timeout OBJECTS — the registry normalizes both to
/// increasing Int ids (the Int return slot must never hold a host object)
/// and drops fired entries.
extern "js" fn js_set_timeout(delay_ms : Int, cb : () -> Unit) -> Int =
  #| (delay, cb) => {
  #|   const store = (globalThis.__moonform_timers ??= { next: 0, map: new Map() });
  #|   const id = ++store.next;
  #|   store.map.set(id, globalThis.setTimeout(() => { store.map.delete(id); cb(); }, delay));
  #|   return id;
  #| }

///|
extern "js" fn js_clear_timeout(id : Int) -> Unit =
  #| (id) => {
  #|   const store = globalThis.__moonform_timers;
  #|   if (store === undefined) { return; }
  #|   const t = store.map.get(id);
  #|   if (t !== undefined) { globalThis.clearTimeout(t); store.map.delete(id); }
  #| }

///|
/// A Clock over real host timers (js target): `now` is wall-clock
/// SECONDS (Int range; diagnostics only), `schedule` is setTimeout, and
/// `cancel` is clearTimeout. Attach with
/// `FormApi::with_clock(real_clock())` to run debounced async validation
/// and asynchronous submissions against real time — the same protocol the
/// VirtualClock drives deterministically in tests.
pub fn real_clock() -> @core.Clock {
  @core.Clock::make(js_now_secs, (delay, cb) => js_set_timeout(delay, cb), id => {
    js_clear_timeout(id)
  })
}
