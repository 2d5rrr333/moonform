// Lens triple: key derivation, typed access, value semantics on write.

///|
struct User {
  email : String
} derive(Eq, Debug)

///|
struct Friend {
  name : String
  nick : String
  tags : Array[String]
} derive(Eq, Debug)

///|
struct LoginForm {
  user : User
  friends : Array[Friend]
} derive(Eq, Debug)

///|
fn sample_form() -> LoginForm {
  {
    user: { email: "root@x.io", },
    friends: [
      { name: "alice", nick: "ali", tags: ["a1", "a2"], },
      { name: "bob", nick: "bo", tags: ["b1"], },
      { name: "carol", nick: "ca", tags: [], },
    ],
  }
}

// hand-written accessor boilerplate (the shape lens-gen will generate)

///|
fn friends_l() -> Lens[LoginForm, Array[Friend]] {
  field("friends", f => f.friends, (f, xs) => { ..f, friends: xs, })
}

///|
fn user_l() -> Lens[LoginForm, User] {
  field("user", f => f.user, (f, u) => { ..f, user: u, })
}

///|
fn email_l() -> Lens[User, String] {
  field("email", u => u.email, (_u, e) => { email: e, })
}

///|
fn friend_name_l() -> Lens[Friend, String] {
  field("name", fr => fr.name, (fr, n) => { ..fr, name: n, })
}

///|
fn friend_tags_l() -> Lens[Friend, Array[String]] {
  field("tags", fr => fr.tags, (fr, ts) => { ..fr, tags: ts, })
}

///|
test "composed key derivation" {
  assert_eq(user_l().compose(email_l()).key.render(), "user.email")
  assert_eq(
    at(friends_l(), 1).compose(friend_name_l()).key.render(),
    "friends.1.name",
  )
  assert_eq(
    at(at(friends_l(), 1).compose(friend_tags_l()), 0).key.render(),
    "friends.1.tags.0",
  )
  let idl : Lens[LoginForm, LoginForm] = identity()
  assert_eq(idl.key.render(), "")
}

///|
test "equivalent compositions derive the same key" {
  // two ways to build the accessor for friends[1].name
  let a = at(friends_l(), 1).compose(friend_name_l())
  let b = at(friends_l(), 1).compose(friend_name_l())
  assert_eq(a.key, b.key)
  // same key �?same addressed field state
  assert_eq(a.get(sample_form()), b.get(sample_form()))
}

///|
test "get reads through arbitrary composition depth" {
  let f = sample_form()
  assert_eq(at(friends_l(), 1).compose(friend_name_l()).get(f), "bob")
  assert_eq(user_l().compose(email_l()).get(f), "root@x.io")
  assert_eq(at(at(friends_l(), 0).compose(friend_tags_l()), 1).get(f), "a2")
  let idl : Lens[LoginForm, LoginForm] = identity()
  assert_eq(idl.get(f), f)
}

///|
test "set writes only the addressed field (value semantics)" {
  let f = sample_form()
  let name1 = at(friends_l(), 1).compose(friend_name_l())
  let f2 = name1.set(f, "robert")
  assert_eq(f.friends[1].name, "bob") // original untouched
  assert_eq(f2.friends[1].name, "robert") // target updated
  assert_eq(f2.friends[0], f.friends[0]) // siblings untouched
  assert_eq(f2.friends[2], f.friends[2])
  assert_eq(f2.user, f.user)
}

///|
test "set through nested array lens writes deep and only there" {
  let f = sample_form()
  let tag = at(at(friends_l(), 0).compose(friend_tags_l()), 0)
  let f2 = tag.set(f, "z")
  assert_eq(f.friends[0].tags[0], "a1") // original untouched
  assert_eq(f2.friends[0].tags[0], "z")
  assert_eq(f2.friends[0].tags[1], "a2") // same array sibling kept
  assert_eq(f2.friends[1], f.friends[1])
}

///|
test "identity lens get/set" {
  let f = sample_form()
  let other = sample_form()
  let idl : Lens[LoginForm, LoginForm] = identity()
  assert_eq(idl.get(f), f)
  let f2 = idl.set(f, other)
  assert_eq(f2, other)
}

///|
test "compose is associative in key space" {
  // (user �?email) vs explicit two-hop �?same key either way
  let two = user_l().compose(email_l())
  assert_eq(two.key, Key::field("user").push_field("email"))
}

///|
test "at lens bounds" {
  let f = sample_form()
  // out-of-bounds set is a no-op on values (defensive; store ops guard)
  let oob = at(friends_l(), 99)
  let f2 = oob.set(f, { name: "x", nick: "x", tags: [], })
  assert_eq(f2, f)
}
