// Spike ②: Clock protocol — capability record (function fields + dispatch methods)
// NOTE: MoonBit traits are not types (no trait fields/params); a record of
// functions is the idiomatic injectable-protocol shape.

///|
pub struct Clock {
  now : () -> Int
  schedule : (Int, () -> Unit) -> Int
  cancel : (Int) -> Unit
}

///|
pub fn Clock::now(self : Clock) -> Int {
  (self.now)()
}

///|
pub fn Clock::schedule(self : Clock, delay : Int, cb : () -> Unit) -> Int {
  (self.schedule)(delay, cb)
}

///|
pub fn Clock::cancel(self : Clock, id : Int) -> Unit {
  (self.cancel)(id)
}

///|
pub struct VirtualClock {
  mut time : Int
  mut next_id : Int
  mut timers : Array[Timer]
}

///|
struct Timer {
  id : Int
  due : Int
  cb : () -> Unit
  mut cancelled : Bool
}

///|
pub fn VirtualClock::make() -> VirtualClock {
  { time: 0, next_id: 1, timers: [], }
}

///|
/// The injectable Clock view over this virtual clock (aliases same state).
pub fn VirtualClock::clock(self : VirtualClock) -> Clock {
  {
    now: () => self.time,
    schedule: (delay, cb) => self.schedule(delay, cb),
    cancel: id => self.cancel(id),
  }
}

///|
pub fn VirtualClock::now(self : VirtualClock) -> Int {
  self.time
}

///|
pub fn VirtualClock::schedule(
  self : VirtualClock,
  delay : Int,
  cb : () -> Unit,
) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  self.timers.push({ id, due: self.time + delay, cb, cancelled: false, })
  id
}

///|
pub fn VirtualClock::cancel(self : VirtualClock, id : Int) -> Unit {
  for t in self.timers {
    if t.id == id {
      t.cancelled = true
    }
  }
}

///|
fn VirtualClock::earliest(self : VirtualClock) -> Timer? {
  let mut best : Timer? = None
  for t in self.timers {
    if t.cancelled {
      continue
    }
    match best {
      None => best = Some(t)
      Some(b) =>
        if t.due < b.due || (t.due == b.due && t.id < b.id) {
          best = Some(t)
        }
    }
  }
  best
}

///|
fn VirtualClock::fire(self : VirtualClock, t : Timer) -> Unit {
  // purge the fired timer and any cancelled ones
  let kept : Array[Timer] = []
  for x in self.timers {
    if x.id != t.id && !x.cancelled {
      kept.push(x)
    }
  }
  self.timers = kept
  if t.due > self.time {
    self.time = t.due
  }
  (t.cb)()
}

///|
/// Advance virtual time by `ms`, firing every timer that becomes due.
/// Timers scheduled by callbacks with due <= target also fire within the tick.
pub fn VirtualClock::tick(self : VirtualClock, ms : Int) -> Unit {
  let target = self.time + ms
  while true {
    match self.earliest() {
      Some(t) => if t.due <= target { self.fire(t) } else { break }
      None => break
    }
  }
  if self.time < target {
    self.time = target
  }
}

///|
/// Fire all pending timers in due order until the queue is empty.
pub fn VirtualClock::run_all(self : VirtualClock) -> Unit {
  while true {
    match self.earliest() {
      Some(t) => self.fire(t)
      None => break
    }
  }
}
