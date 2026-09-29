// struct Address

///|
fn address_city_l() -> @core.Lens[Address, String] {
  @core.field("city", v => v.city, (v, x) => { ..v, city: x, })
}

///|
fn address_zip_l() -> @core.Lens[Address, Int] {
  @core.field("zip", v => v.zip, (v, x) => { ..v, zip: x, })
}

// struct Profile

///|
fn profile_nickname_l() -> @core.Lens[Profile, String] {
  @core.field("nickname", v => v.nickname, (v, x) => { ..v, nickname: x, })
}

///|
fn profile_age_l() -> @core.Lens[Profile, Int] {
  @core.field("age", v => v.age, (v, x) => { ..v, age: x, })
}
