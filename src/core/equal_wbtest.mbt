// Deep-equality protocol: derive(Eq) is deep; dirty derives from it;
// writes never mutate the original (value semantics).

///|
struct Addr {
  city : String
} derive(Eq, Debug)

///|
struct Profile {
  addr : Addr
  hobbies : Array[String]
} derive(Eq, Debug)

///|
struct Account {
  profile : Profile
  age : Int
} derive(Eq, Debug)

///|
fn defaults() -> Account {
  { profile: { addr: { city: "hz", }, hobbies: ["a", "b"], }, age: 30, }
}

///|
fn profile_l() -> Lens[Account, Profile] {
  field("profile", a => a.profile, (a, p) => { ..a, profile: p, })
}

///|
fn city_l() -> Lens[Profile, String] {
  field("city", p => p.addr.city, (p, c) => { ..p, addr: { city: c, }, })
}

///|
fn hobbies_l() -> Lens[Profile, Array[String]] {
  field("hobbies", p => p.hobbies, (p, hs) => { ..p, hobbies: hs, })
}

///|
fn age_l() -> Lens[Account, Int] {
  field("age", a => a.age, (a, n) => { ..a, age: n, })
}

///|
test "deeply equal distinct instances are not dirty" {
  let a = defaults()
  let b = defaults() // separate instance, equal content
  assert_true(values_equal(a, b))
  assert_false(field_is_dirty(age_l(), a, b))
  assert_false(field_is_dirty(profile_l(), a, b))
  let city = profile_l().compose(city_l())
  assert_false(field_is_dirty(city, a, b))
}

///|
test "field write makes that field dirty, not others" {
  let d = defaults()
  let current = age_l().set(d, 31)
  assert_true(field_is_dirty(age_l(), current, d))
  assert_false(field_is_dirty(profile_l(), current, d))
  assert_false(values_equal(current, d))
}

///|
test "writing back the default clears dirty" {
  let d = defaults()
  let touched = age_l().set(d, 31)
  let restored = age_l().set(touched, 30)
  assert_false(field_is_dirty(age_l(), restored, d))
  assert_true(values_equal(restored, d))
}

///|
test "deep nested array edit is dirty at every enclosing level" {
  let d = defaults()
  let hobbies = profile_l().compose(hobbies_l())
  // edit one element inside the array (through an index lens on String)
  let elem = at(hobbies, 1)
  let current = elem.set(d, "c")
  assert_true(field_is_dirty(elem, current, d))
  assert_true(field_is_dirty(hobbies, current, d))
  assert_true(field_is_dirty(profile_l(), current, d))
  // sibling field untouched
  assert_false(field_is_dirty(age_l(), current, d))
}

///|
test "writes never mutate the original value" {
  let d = defaults()
  let current = profile_l().compose(city_l()).set(d, "sh")
  assert_eq(d.profile.addr.city, "hz") // original intact
  assert_eq(current.profile.addr.city, "sh")
  assert_eq(d.profile.hobbies, current.profile.hobbies)
}

///|
pub extend Account with Debug::{to_repr}

///|
pub extend Account with Eq::{not_equal, equal}

///|
pub extend Addr with Debug::{to_repr}

///|
pub extend Addr with Eq::{not_equal, equal}

///|
pub extend Profile with Debug::{to_repr}

///|
pub extend Profile with Eq::{not_equal, equal}
