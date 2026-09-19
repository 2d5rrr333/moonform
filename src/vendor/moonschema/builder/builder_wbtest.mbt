///|
test "object 构建器: 默认必填 + optional + strict 降级为标准 JSON Schema" {
  let user = object({
    "name": string().min_len(1).max_len(50),
    "age": integer().min(0).max(150).optional(),
    "email": string().email(),
  }).strict()
  inspect(
    user.to_schema().stringify(),
    content="{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":50},\"age\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":150},\"email\":{\"type\":\"string\",\"format\":\"email\"}},\"required\":[\"name\",\"email\"],\"additionalProperties\":false}",
  )
}

///|
test "nullable / catchall / 构建器到校验器端到端" {
  let s = object({
    "id": integer().min(1),
    "note": string().nullable().optional(),
    "meta": any(),
  }).catchall(string())
  let v = s.compile()
  let good = Json::object({
    "id": Json::number(1),
    "meta": Json::number(2.5),
    "extra": Json::string("ok"),
  })
  inspect(v.check(good), content="true")
  let bad = Json::object({ "id": Json::number(0), "extra": Json::number(1) })
  inspect(v.check(bad), content="false")
  // nullable: null 通过 string().nullable()
  let ok_null = Json::object({
    "id": Json::number(1),
    "note": Json::null(),
    "meta": Json::string("m"),
  })
  inspect(v.check(ok_null), content="true")
}

///|
test "email 格式断言在 builder 层默认开启" {
  let v = object({ "email": string().email() }).compile()
  inspect(
    v.check(Json::object({ "email": Json::string("a@b.co") })),
    content="true",
  )
  inspect(
    v.check(Json::object({ "email": Json::string("broken") })),
    content="false",
  )
}

///|
test "enum_ / literal / array 构建器" {
  let s = object({
    "role": enum_([Json::string("admin"), Json::string("user")]),
    "version": literal(Json::number(2)),
    "tags": array(string()).unique_items().max_items(3),
  })
  let v = s.compile()
  inspect(
    v.check(
      Json::object({
        "role": Json::string("admin"),
        "version": Json::number(2),
        "tags": Json::array([Json::string("a"), Json::string("b")]),
      }),
    ),
    content="true",
  )
  inspect(
    v.check(
      Json::object({
        "role": Json::string("guest"),
        "version": Json::number(2),
        "tags": Json::array([Json::string("a")]),
      }),
    ),
    content="false",
  )
  inspect(
    v.check(
      Json::object({
        "role": Json::string("user"),
        "version": Json::number(2),
        "tags": Json::array([Json::string("a"), Json::string("a")]),
      }),
    ),
    content="false",
  )
}

///|
test "to_schema 与手写 JSON Schema 互通（compile 侧验证）" {
  // builder 降级的文档可被引擎直接消费；这里验证 number 类型构建器
  let price = number().gt(0).multiple_of(0.5)
  let v = price.compile()
  inspect(v.check(Json::number(9.5)), content="true")
  inspect(v.check(Json::number(-1)), content="false")
}

///|
test "satisfy: builder 追加跨字段规则" {
  let order = object({
      "start": string(),
      "end": string(),
      "total": number(),
      "items": array(object({ "price": number(), "qty": number() }).optional()),
    })
    .satisfy("end > start")
    .satisfy("items[0].price * items[0].qty == total")
  // 降级文档带 x-rules
  inspect(order.to_schema().stringify().contains("x-rules"), content="true")
  let v = order.compile()
  let good = Json::object({
    "start": Json::string("2026-01-01"),
    "end": Json::string("2026-12-31"),
    "total": Json::number(20),
    "items": Json::array([
      Json::object({ "price": Json::number(10), "qty": Json::number(2) }),
    ]),
  })
  inspect(v.check(good), content="true")
  let bad = Json::object({
    "start": Json::string("2026-01-01"),
    "end": Json::string("2026-02-01"),
    "total": Json::number(1),
    "items": Json::array([
      Json::object({ "price": Json::number(10), "qty": Json::number(2) }),
    ]),
  })
  inspect(v.check(bad), content="false")
}
