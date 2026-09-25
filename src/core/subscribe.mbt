///|
/// What changed about a field or the form — used by subscribers that
/// filter the change kinds they care about.
pub enum ChangeKind {
  Value
  Meta
} derive(Eq, Debug)

///|
/// Convenience constructor for subscribers watching both value and meta
/// changes (the common adapter case).
pub fn ChangeKind::value_and_meta() -> Array[ChangeKind] {
  [Value, Meta]
}

///|
pub(all) struct Sub {
  id : Int
  key : Key? // None = whole form
  /// Some(p) = every key under p, including p itself (prefix matching
  /// overrides `key`)
  prefix : Key?
  kinds : Array[ChangeKind]? // None = all kinds
  cb : () -> Unit
}

///|
/// Subscription bookkeeping with stable identity (monotonic ids — the
/// upstream v2 lesson: never array indices) plus batched notification:
/// inside `batch`, notifications coalesce to one callback per subscriber.
pub struct Subscriptions {
  mut next_id : Int
  mut subs : Array[Sub]
  mut batch_depth : Int
  mut pending_all : Bool
  mut pending : Array[(Key, ChangeKind)]
}

///|
pub fn Subscriptions::make() -> Subscriptions {
  { next_id: 1, subs: [], batch_depth: 0, pending_all: false, pending: [], }
}

///|
/// Subscribe to any form change. Returns a stable handle for unsubscribe.
pub fn Subscriptions::subscribe(self : Subscriptions, cb : () -> Unit) -> Int {
  self.add(None, None, None, cb)
}

///|
/// Subscribe to changes of one field (exact key match), optionally only
/// certain change kinds.
pub fn Subscriptions::subscribe_field(
  self : Subscriptions,
  key : Key,
  kinds? : Array[ChangeKind],
  cb : () -> Unit,
) -> Int {
  self.add(Some(key), None, kinds, cb)
}

///|
/// Subscribe to changes of every key under `prefix` (including the prefix
/// key itself), optionally only certain change kinds — the natural
/// subscription for group/subtree adapters, whose snapshots derive from
/// all child fields.
pub fn Subscriptions::subscribe_under(
  self : Subscriptions,
  prefix : Key,
  kinds? : Array[ChangeKind],
  cb : () -> Unit,
) -> Int {
  self.add(None, Some(prefix), kinds, cb)
}

///|
fn Subscriptions::add(
  self : Subscriptions,
  key : Key?,
  prefix : Key?,
  kinds : Array[ChangeKind]?,
  cb : () -> Unit,
) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  self.subs.push({ id, key, prefix, kinds, cb, })
  id
}

///|
/// Unsubscribe by handle (stable identity). Missing handle is a no-op.
pub fn Subscriptions::unsubscribe(self : Subscriptions, id : Int) -> Unit {
  let kept : Array[Sub] = []
  for s in self.subs {
    if s.id != id {
      kept.push(s)
    }
  }
  self.subs = kept
}

///|
fn sub_matches(sub : Sub, key : Key, kind : ChangeKind) -> Bool {
  let key_ok = match sub.prefix {
    Some(p) => key.has_prefix(p)
    None =>
      match sub.key {
        None => true
        Some(k) => k == key
      }
  }
  let kind_ok = match sub.kinds {
    None => true
    Some(ks) => {
      let mut hit = false
      for k in ks {
        if k == kind {
          hit = true
        }
      }
      hit
    }
  }
  key_ok && kind_ok
}

///|
/// Record (or fire) a change of `kind` on `key`. Callbacks may unsubscribe
/// (themselves or others) mid-notify: a snapshot of the subscriber list is
/// iterated and each subscriber is re-checked for liveness after every
/// callback, so removals take effect immediately without breaking the
/// in-flight dispatch.
fn Subscriptions::notify(
  self : Subscriptions,
  key : Key,
  kind : ChangeKind,
) -> Unit {
  if self.batch_depth > 0 {
    self.pending.push((key, kind))
  } else {
    let snapshot = self.subs.copy()
    for s in snapshot {
      if self.is_live(s.id) && sub_matches(s, key, kind) {
        (s.cb)()
      }
    }
  }
}

///|
/// Record (or fire) a change affecting every subscriber (reset, update).
/// Mid-notify unsubscribes are honored (see `notify`).
fn Subscriptions::notify_all(self : Subscriptions) -> Unit {
  if self.batch_depth > 0 {
    self.pending_all = true
  } else {
    let snapshot = self.subs.copy()
    for s in snapshot {
      if self.is_live(s.id) {
        (s.cb)()
      }
    }
  }
}

///|
/// Run `f` with notifications coalesced: each subscriber fires at most once
/// at the end of the outermost batch. Batches nest. Mid-flush unsubscribes
/// are honored (see `notify`).
pub fn Subscriptions::batch(self : Subscriptions, f : () -> Unit) -> Unit {
  self.batch_depth = self.batch_depth + 1
  f()
  self.batch_depth = self.batch_depth - 1
  if self.batch_depth == 0 {
    let pending = self.pending
    let pending_all = self.pending_all
    self.pending = []
    self.pending_all = false
    let snapshot = self.subs.copy()
    for s in snapshot {
      if !self.is_live(s.id) {
        continue // unsubscribed by an earlier callback in this flush
      }
      let mut fire = pending_all
      if !fire {
        for pair in pending {
          let (k, kind) = pair
          if sub_matches(s, k, kind) {
            fire = true
            break
          }
        }
      }
      if fire {
        (s.cb)()
      }
    }
  }
}

///|
/// Is the subscription with `id` still registered?
fn Subscriptions::is_live(self : Subscriptions, id : Int) -> Bool {
  for s in self.subs {
    if s.id == id {
      return true
    }
  }
  false
}

///|
pub extend ChangeKind with Debug::{to_repr}

///|
pub extend ChangeKind with Eq::{not_equal, equal}
