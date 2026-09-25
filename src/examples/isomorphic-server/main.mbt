// Isomorphic validation — the SERVER side (native target): the SAME shared
// validators replayed through a fresh form instance as the final submission
// gate — no JS, no serialization boundary, no duplicated logic.
// Headless verification: `moon run src/examples/isomorphic-server --target native`.

///|
fn main {
  // a hostile submission: the client-side UI could be bypassed entirely
  let hostile : @isomorphic.Registration = {
    username: "x",
    email: "nope",
    age: 9,
    accept_terms: false,
  }
  let rejected = @isomorphic.server_review(hostile)
  if rejected.length() != 4 {
    abort("expected all four fields rejected, got \{rejected.length()}")
  }
  println("server: hostile payload rejected on every field")
  for pair in rejected {
    let (field, errs) = pair
    println("  \{field}: \{errs.length()} error(s)")
  }
  // the corrected payload passes the same gate
  let good : @isomorphic.Registration = {
    username: "moonbit",
    email: "user@example.com",
    age: 20,
    accept_terms: true,
  }
  let accepted = @isomorphic.server_review(good)
  if accepted.length() != 0 {
    abort("corrected payload should pass")
  }
  println("server: corrected payload accepted")
  println("isomorphic server: all checks passed")
}
