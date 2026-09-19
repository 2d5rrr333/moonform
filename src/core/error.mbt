///|
/// Validation cause — when a validator ran. Mirrors upstream
/// `ValidationCause`; selects the errorMap slot a result lands in.
pub enum ValidationCause {
  Mount
  Change
  Blur
  Submit
  Server
} derive(Eq, Debug)

///|
/// Constructors for blackbox callers (cross-package enum values are
/// read-only; these also serve the onServer slot reserved for future
/// server-side validation).
pub fn ValidationCause::mount() -> ValidationCause {
  Mount
}

///|
pub fn ValidationCause::change() -> ValidationCause {
  Change
}

///|
pub fn ValidationCause::blur() -> ValidationCause {
  Blur
}

///|
pub fn ValidationCause::submit() -> ValidationCause {
  Submit
}

///|
pub fn ValidationCause::server() -> ValidationCause {
  Server
}

///|
/// Per-cause error slots for one field. `None` = no result recorded for
/// that cause (upstream: absent errorMap key). Slots are replaced, not
/// merged, when their cause re-validates.
pub struct ErrorMap {
  on_mount : Array[String]?
  on_change : Array[String]?
  on_blur : Array[String]?
  on_submit : Array[String]?
  on_server : Array[String]?
} derive(Eq, Debug)

///|
pub fn ErrorMap::empty() -> ErrorMap {
  {
    on_mount: None,
    on_change: None,
    on_blur: None,
    on_submit: None,
    on_server: None,
  }
}

///|
/// Errors for one cause slot.
pub fn ErrorMap::get(
  self : ErrorMap,
  cause : ValidationCause,
) -> Array[String]? {
  match cause {
    Mount => self.on_mount
    Change => self.on_change
    Blur => self.on_blur
    Submit => self.on_submit
    Server => self.on_server
  }
}

///|
/// Functional update of one cause slot (`None` clears the slot).
pub fn ErrorMap::set(
  self : ErrorMap,
  cause : ValidationCause,
  errors : Array[String]?,
) -> ErrorMap {
  match cause {
    Mount => { ..self, on_mount: errors, }
    Change => { ..self, on_change: errors, }
    Blur => { ..self, on_blur: errors, }
    Submit => { ..self, on_submit: errors, }
    Server => { ..self, on_server: errors, }
  }
}

///|
/// Flattened errors in fixed lifecycle order (Mount, Change, Blur, Submit,
/// Server). Documented deviation: upstream flattens in JS-object insertion
/// order, which approximates this in the common flows.
pub fn ErrorMap::flatten(self : ErrorMap) -> Array[String] {
  let out : Array[String] = []
  fn push(slot : Array[String]?) -> Unit {
    match slot {
      Some(errs) =>
        for e in errs {
          out.push(e)
        }
      None => ()
    }
  }
  push(self.on_mount)
  push(self.on_change)
  push(self.on_blur)
  push(self.on_submit)
  push(self.on_server)
  out
}

///|
pub fn ErrorMap::has_errors(self : ErrorMap) -> Bool {
  self.flatten().length() > 0
}
