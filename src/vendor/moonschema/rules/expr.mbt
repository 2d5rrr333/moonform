///|
/// 跨字段规则 DSL 的表达式 AST。
///
/// 语法（优先级从低到高）：
/// ```text
///   or  := and ("||" and)*
///   and := not ("&&" not)*
///   not := "!" not | cmp
///   cmp := add (("==" | "!=" | "<" | "<=" | ">" | ">=") add)?
///   add := mul (("+" | "-") mul)*
///   mul := unary (("*" | "/" | "%") unary)*
///   unary := "-" unary | primary
///   primary := number | string | true | false | null | path | "(" or ")"
///   path := ident ("." ident | "[" int "]")*
/// ```
///
/// 路径相对于声明 `x-rules` 的模式节点对应的实例，例如
/// `end_date > start_date`、`items[0].price * items[0].qty == total`。
pub(all) enum Expr {
  ENum(Double)
  EStr(String)
  EBool(Bool)
  ENull
  EPath(Array[PathSeg])
  ENot(Expr)
  EArith(String, Expr, Expr)
  ECmp(String, Expr, Expr)
  ELogic(String, Expr, Expr)
} derive(Eq)

///|
/// 路径段：对象键或数组下标。
pub(all) enum PathSeg {
  PKey(String)
  PIndex(Int)
} derive(Eq)

///|
/// 表达式不合法时抛出的错误（编译期即可发现拼写与语法问题）。
pub(all) suberror ExprError {
  /// 完整的错误描述（含出错位置）
  ExprSyntax(String)
} derive(Eq)

///|
pub impl Show for ExprError with fn output(self, logger) {
  match self {
    ExprSyntax(msg) => logger.write_string(msg)
  }
}

///|
/// 表达式的求值结果。
priv enum Value {
  VBool(Bool)
  VNum(Double)
  VStr(String)
  VNull
  /// 路径解析失败（字段缺失或类型不通）。作为"毒值"参与任何比较都为假。
  VMissing
}

///|
fn Value::truthy(self : Value) -> Bool {
  match self {
    VBool(b) => b
    _ => false
  }
}

///|
/// 便捷入口：解析 JSON 实例文本（独立使用规则求值时构造实例用）。
pub fn parse_instance(text : String) -> Json raise @json.ParseError {
  @json.parse(text)
}
