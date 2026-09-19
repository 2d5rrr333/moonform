///|
/// 构造测试实例的便捷函数。
fn j(txt : String) -> Json raise {
  @json.parse(txt)
}

///|
fn holds(expr_src : String, instance : String) -> Bool raise {
  let e = compile_expr(expr_src)
  rule_holds(e, j(instance))
}

///|
fn syntax_error(expr_src : String) -> String {
  try {
    ignore(compile_expr(expr_src))
    "(no error)"
  } catch {
    ExprSyntax(m) => m
  }
}

///|
test "比较与算术" {
  inspect(holds("1 + 2 * 3 == 7", "null"), content="true")
  inspect(holds("(1 + 2) * 3 == 9", "null"), content="true")
  inspect(holds("10 / 4 == 2.5", "null"), content="true")
  inspect(holds("10 % 4 == 2", "null"), content="true")
  inspect(holds("-3 < 2", "null"), content="true")
  inspect(holds("\"abc\" < \"abd\"", "null"), content="true")
  inspect(holds("\"a\" == \"a\"", "null"), content="true")
  inspect(holds("1 != 2", "null"), content="true")
  // 跨类型比较为假
  inspect(holds("1 == \"1\"", "null"), content="false")
  inspect(holds("null == null", "null"), content="true")
  // 除零不可满足
  inspect(holds("1 / 0 > 0", "null"), content="false")
}

///|
test "逻辑与优先级" {
  inspect(holds("true || false", "null"), content="true")
  inspect(holds("false && true", "null"), content="false")
  inspect(holds("!false", "null"), content="true")
  inspect(holds("!(1 > 2)", "null"), content="true")
  inspect(holds("true || false && false", "null"), content="true")
  inspect(holds("(true || false) && false", "null"), content="false")
}

///|
test "路径解析：点号 / 下标 / 嵌套" {
  let inst =
    #|{
    #|  "start": "2026-01-01",
    #|  "end": "2026-12-31",
    #|  "address": { "city": "hz", "zip": 310000 },
    #|  "items": [ { "price": 10, "qty": 2 }, { "price": 3, "qty": 1 } ],
    #|  "total": 20
    #|}
  let root = j(inst)
  inspect(rule_holds(compile_expr("end > start"), root), content="true")
  inspect(
    rule_holds(compile_expr("address.zip == 310000"), root),
    content="true",
  )
  inspect(
    rule_holds(compile_expr("items[0].price * items[0].qty == total"), root),
    content="true",
  )
  inspect(
    rule_holds(compile_expr("items[0].price + items[1].price == 13"), root),
    content="true",
  )
  // items[9] 越界缺失 → 按"缺失即藐视通过"的文档化语义直接通过
  inspect(rule_holds(compile_expr("items[9] == null"), root), content="true")
  // ISO 日期字符串按字典序比较即日期比较
  inspect(rule_holds(compile_expr("start < end"), root), content="true")
}

///|
test "缺失即藐视通过；出现则必须满足" {
  // 两个字段都缺失 → 规则通过
  inspect(holds("end > start", "{}"), content="true")
  // 只出现一个（值大小关系无法判定）→ 通过
  inspect(holds("end > start", "{\"start\": 1}"), content="true")
  // 都出现且不满足 → 失败
  inspect(holds("end > start", "{\"start\": 2, \"end\": 1}"), content="false")
  // 都出现且满足 → 通过
  inspect(holds("end > start", "{\"start\": 1, \"end\": 2}"), content="true")
}

///|
test "语法错误在编译期暴露" {
  let m1 = syntax_error("end >")
  let hit1 = m1.contains("syntax error")
  inspect(hit1, content="true")
  let m2 = syntax_error("(1 +")
  let hit2 = m2.contains("syntax error")
  inspect(hit2, content="true")
  let m3 = syntax_error("1 ~ 2")
  let hit3 = m3.contains("unexpected character")
  inspect(hit3, content="true")
  let m4 = syntax_error("\"unterminated")
  let hit4 = m4.contains("unterminated")
  inspect(hit4, content="true")
  let m5 = syntax_error("a.")
  let hit5 = m5.contains("expected identifier")
  inspect(hit5, content="true")
}
