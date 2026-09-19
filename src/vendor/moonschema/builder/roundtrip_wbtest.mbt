///|
/// 种子化伪随机数发生器（LCG）——性质测试需要可复现的"随机"实例。
priv struct Lcg {
  mut state : UInt64
}

///|
fn Lcg::next(self : Lcg) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state >> 33
}

///|
fn Lcg::new(seed : UInt64) -> Lcg {
  { state: seed, }
}

///|
/// 随机 JSON 字符串（小写字母，长度 1..12）。
fn rand_string(lcg : Lcg) -> String {
  let len = (lcg.next() % 12UL).to_int() + 1
  let b = StringBuilder()
  for _i in 0..<len {
    let c = (97 + lcg.next().to_int() % 26).unsafe_to_char()
    b.write_char(c)
  }
  b.to_string()
}

///|
/// 随机数（含整数/小数/负数形态）。
fn rand_number(lcg : Lcg) -> Json {
  let kind = lcg.next() % 3UL
  let v = lcg.next().to_double() % 1000.0
  if kind == 0UL {
    Json::number(v.floor())
  } else if kind == 1UL {
    Json::number(-v / 7.0)
  } else {
    Json::number(v / 3.0)
  }
}

///|
/// 深度受限的随机 JSON 实例：混合所有类型与嵌套结构。
fn rand_instance(lcg : Lcg, depth : Int) -> Json {
  let kind = lcg.next() % 10UL
  if depth <= 0 {
    return rand_number(lcg)
  }
  if kind < 2UL {
    Json::string(rand_string(lcg))
  } else if kind < 4UL {
    rand_number(lcg)
  } else if kind < 5UL {
    match lcg.next() % 2UL {
      0UL => Json::boolean(true)
      _ => Json::boolean(false)
    }
  } else if kind < 6UL {
    Json::null()
  } else if kind < 8UL {
    let n = lcg.next() % 4UL
    let arr : Array[Json] = []
    for _i in 0..<n.to_int() {
      arr.push(rand_instance(lcg, depth - 1))
    }
    Json::array(arr)
  } else {
    let m = lcg.next() % 4UL
    let obj : Map[String, Json] = Map([], capacity=4)
    for _i in 0..<m.to_int() {
      obj[rand_string(lcg)] = rand_instance(lcg, depth - 1)
    }
    Json::object(obj)
  }
}

///|
/// 测试对象：zod 风格构建器描述的"用户订单"模式。
fn order_schema() -> SchemaBuilder {
  object({
    "id": integer().min(1),
    "name": string().min_len(1).max_len(12),
    "email": string().email().optional(),
    "role": enum_([Json::string("admin"), Json::string("user")]),
    "score": number().min(0.0).max(100.0).optional(),
    "tags": array(string()).max_items(3).optional(),
    "meta": any().optional(),
  }).strict()
}

///|
/// 性质 1（序列化 roundtrip）：`to_schema()` 文档经 stringify → parse
/// 往返后编译，与构建器直接编译的判定对全部随机实例完全一致。
test "roundtrip: builder 文档序列化往返判定一致" {
  let builder = order_schema()
  let direct = builder.compile()
  let doc = builder.to_schema()
  let via_text = @schema.compile(@json.parse(doc.stringify()))
  let lcg = Lcg::new(20260908UL)
  let mut agree = 0
  for i in 0..<500 {
    // 前 10 个为确定合法的实例，保证两类判定都出现
    let inst = if i < 10 {
      Json::object({
        "id": Json::number(1),
        "name": Json::string("abc"),
        "role": Json::string("user"),
      })
    } else {
      rand_instance(lcg, 2)
    }
    let a = direct.check(inst)
    let b = via_text.check(inst)
    inspect(a == b, content="true")
    if a {
      agree += 1
    }
  }
  inspect(agree >= 10 && agree < 500, content="true")
}

///|
/// 性质 2（编译确定性）：同一文档重复编译，对全部随机实例判定相同。
test "roundtrip: 重复编译判定确定" {
  let doc = order_schema().to_schema()
  let v1 = @schema.compile(@json.parse(doc.stringify()))
  let v2 = @schema.compile(@json.parse(doc.stringify()))
  let lcg = Lcg::new(777UL)
  for _i in 0..<300 {
    let inst = rand_instance(lcg, 2)
    inspect(v1.check(inst) == v2.check(inst), content="true")
  }
}

///|
/// 性质 3（fast/slow 互恰）：check 判定失败当且仅当错误列表非空。
test "roundtrip: check 与 validate 互恰" {
  let v = order_schema().compile()
  let lcg = Lcg::new(4242UL)
  for _i in 0..<300 {
    let inst = rand_instance(lcg, 2)
    let fast = v.check(inst)
    let full = v.validate(inst)
    inspect(fast == full.is_empty(), content="true")
  }
}
