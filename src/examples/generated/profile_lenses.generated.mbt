// struct Profile

///|
fn profile_nickname_l() -> @core.Lens[Profile, String] {
  @core.field("nickname", v => v.nickname, (v, x) => { ..v, nickname: x, })
}

///|
fn profile_age_l() -> @core.Lens[Profile, Int] {
  @core.field("age", v => v.age, (v, x) => { ..v, age: x, })
}
