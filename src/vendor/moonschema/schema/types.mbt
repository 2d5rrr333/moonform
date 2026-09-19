///|
/// JSON Schema 2020-12 认可的实例类型。
/// `JTInteger` 不是独立的 JSON 类型，而是 "number 且没有小数部分" 的约束。
pub(all) enum JsonType {
  JTNull
  JTBoolean
  JTObject
  JTArray
  JTNumber
  JTString
  JTInteger
} derive(Eq)

///|
fn JsonType::parse(s : String, path : String) -> JsonType raise CompileError {
  match s {
    "null" => JTNull
    "boolean" => JTBoolean
    "object" => JTObject
    "array" => JTArray
    "number" => JTNumber
    "string" => JTString
    "integer" => JTInteger
    _ => raise InvalidSchema(path, "invalid type name \"\{s}\"")
  }
}

///|
fn JsonType::label(self : JsonType) -> String {
  match self {
    JTNull => "null"
    JTBoolean => "boolean"
    JTObject => "object"
    JTArray => "array"
    JTNumber => "number"
    JTString => "string"
    JTInteger => "integer"
  }
}

///|
fn Json::json_type(self : Json) -> JsonType {
  match self {
    Null => JTNull
    True | False => JTBoolean
    Object(_) => JTObject
    Array(_) => JTArray
    Number(_) => JTNumber
    String(_) => JTString
  }
}

///|
fn Json::matches_type(self : Json, t : JsonType) -> Bool {
  if t is JTInteger {
    match self {
      Number(n, ..) => !n.is_nan() && n == n.floor()
      _ => false
    }
  } else {
    self.json_type() == t
  }
}

///|
/// 实例校验失败的一条错误。
///
/// - `keyword`：触发错误的关键词，如 `"required"`
/// - `instance_path`：出错数据的位置（RFC 6901 JSON Pointer，如 `"/address/zip"`）
/// - `schema_path`：触发错误的关键词在模式中的位置（如 `"#/properties/age/minimum"`）
/// - `message`：人类可读的错误描述（ajv 风格英文消息）
pub(all) struct ValidationError {
  keyword : String
  instance_path : String
  schema_path : String
  message : String
} derive(Eq, ToJson)

///|
/// 把错误列表渲染为多行文本，适合日志输出与测试快照。
pub fn summarize(errors : Array[ValidationError]) -> String {
  let b = StringBuilder()
  let mut first = true
  for e in errors {
    if !first {
      b.write_string("\n")
    }
    first = false
    let loc = if e.instance_path == "" { "(root)" } else { e.instance_path }
    b.write_string("\{loc}: \{e.message} [\{e.keyword} @ \{e.schema_path}]")
  }
  b.to_string()
}

///|
/// 模式文档本身不合法时抛出的错误（区别于"实例校验失败"）。
pub(all) suberror CompileError {
  /// (schema_path, 原因)
  InvalidSchema(String, String)
  /// (schema_path, 关键词名) —— strict 模式下遇到不支持的关键词
  UnsupportedKeyword(String, String)
} derive(Eq)

///|
pub impl Show for CompileError with fn output(self, logger) {
  match self {
    InvalidSchema(path, reason) =>
      logger.write_string("invalid schema at \{path}: \{reason}")
    UnsupportedKeyword(path, kw) =>
      logger.write_string(
        "unsupported keyword \"\{kw}\" at \{path} (strict mode)",
      )
  }
}

///|
/// 校验错误消息的语言（影响实例校验失败的消息文本；
/// 模式编译错误面向开发者，始终为英文）。
pub(all) enum Locale {
  EN
  ZH
} derive(Eq)

///|
/// 按语言挑选消息文案。
fn tr(locale : Locale, en : String, zh : String) -> String {
  match locale {
    EN => en
    ZH => zh
  }
}

///|
/// 编译选项（见 `compile`）。
pub struct CompileOptions {
  /// strict 模式（默认开启，ajv 风格）：引擎不支持的关键词直接报错，
  /// 避免拼写错误被静默忽略；`x-` 前缀的扩展关键词始终放行。
  /// 传 `false` 则按规范忽略未知关键词。
  strict : Bool
  /// 按 2020-12 规范，`format` 默认只是 annotation（不断言）。
  /// 打开后对认识的 format（email / uuid / ipv4）进行断言。
  assert_format : Bool
  /// 校验错误消息语言，默认英文。
  locale : Locale
} derive(Eq)

///|
pub fn CompileOptions::new(
  strict? : Bool = true,
  assert_format? : Bool = false,
  locale? : Locale = EN,
) -> CompileOptions {
  { strict, assert_format, locale, }
}

///|
/// 编译上下文：根文档 + `$ref` 惰性编译缓存（支持递归模式）。
struct Ctx {
  root : Json
  strict : Bool
  assert_format : Bool
  locale : Locale
  cache : Map[String, Schema]
}

///|
/// 编译后的模式节点。
enum Node {
  BoolNode(Bool)
  SchemaNode(Keywords)
}

///|
/// 一个模式节点上收集到的全部关键词。
priv struct Keywords {
  mut ref_ : String?
  mut typ : Array[JsonType]?
  mut enum_ : Array[Json]?
  mut const_ : Json?
  // 数值
  mut multiple_of : Double?
  mut maximum : Double?
  mut exclusive_maximum : Double?
  mut minimum : Double?
  mut exclusive_minimum : Double?
  // 字符串
  mut min_length : Int?
  mut max_length : Int?
  mut format : String?
  mut pattern : (@string.Regex, String)?
  // 数组
  mut min_items : Int?
  mut max_items : Int?
  mut unique_items : Bool?
  mut prefix_items : Array[Schema]?
  mut items : Schema?
  mut contains : Schema?
  mut min_contains : Int?
  mut max_contains : Int?
  // 对象
  mut min_properties : Int?
  mut max_properties : Int?
  mut required : Array[String]?
  mut properties : Map[String, Schema]?
  mut pattern_properties : Array[(@string.Regex, String, Schema)]?
  mut property_names : Schema?
  mut additional_closed : Bool?
  mut additional : Schema?
  mut dependent_required : Map[String, Array[String]]?
  mut dependent_schemas : Map[String, Schema]?
  // 跨字段动态规则（引擎扩展关键词 x-rules，路径相对本节点实例）
  mut rule_srcs : Array[String]?
  mut rules : Array[@rules.Expr]?
  // 组合器
  mut all_of : Array[Schema]?
  mut any_of : Array[Schema]?
  mut one_of : Array[Schema]?
  mut not_ : Schema?
  mut if_ : Schema?
  mut then_ : Schema?
  mut else_ : Schema?
}

///|
fn Keywords::empty() -> Keywords {
  {
    ref_: None,
    typ: None,
    enum_: None,
    const_: None,
    multiple_of: None,
    maximum: None,
    exclusive_maximum: None,
    minimum: None,
    exclusive_minimum: None,
    min_length: None,
    max_length: None,
    format: None,
    pattern: None,
    min_items: None,
    max_items: None,
    unique_items: None,
    prefix_items: None,
    items: None,
    contains: None,
    min_contains: None,
    max_contains: None,
    min_properties: None,
    max_properties: None,
    required: None,
    properties: None,
    pattern_properties: None,
    property_names: None,
    additional_closed: None,
    additional: None,
    dependent_required: None,
    dependent_schemas: None,
    rule_srcs: None,
    rules: None,
    all_of: None,
    any_of: None,
    one_of: None,
    not_: None,
    if_: None,
    then_: None,
    else_: None,
  }
}

///|
/// 已编译的 Schema（对应 ajv 的 compiled schema）：不可变、可跨请求复用。
pub struct Schema {
  node : Node
  ctx : Ctx
}

///|
/// 校验一个 JSON 实例，返回全部错误；空数组表示通过。
///
/// 对应 ajv 的 `validate` + `errors`：
/// ```moonbit nocheck
/// let v = compile(schema)
/// let errors = v.validate(instance)
/// if errors.length() > 0 { println(summarize(errors)) }
/// ```
pub fn Schema::validate(
  self : Schema,
  instance : Json,
) -> Array[ValidationError] {
  let errors : Array[ValidationError] = []
  let _ = validate_node(self, self.node, instance, [], ["#"], errors)
  errors
}

///|
/// 便捷方法：实例是否通过校验。
pub fn Schema::check(self : Schema, instance : Json) -> Bool {
  self.validate(instance).is_empty()
}

///|
/// 按 JSON Schema 语义的深度相等：数值按值比较（`1` 与 `1.0` 相等），
/// 不依赖解析器保留的字面表示（repr）。
fn json_eq(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (Number(x, ..), Number(y, ..)) => x == y
    (String(x), String(y)) => x == y
    (Array(x), Array(y)) =>
      if x.length() != y.length() {
        false
      } else {
        let mut same = true
        for i in 0..<x.length() {
          if !json_eq(x[i], y[i]) {
            same = false
          }
        }
        same
      }
    (Object(x), Object(y)) =>
      if x.length() != y.length() {
        false
      } else {
        let mut same = true
        for k, v in x {
          match y.get(k) {
            Some(v2) => if !json_eq(v, v2) { same = false }
            None => same = false
          }
        }
        same
      }
    _ => false
  }
}

///|
/// 字符串的 Unicode 码点数。`minLength`/`maxLength` 的规范计量单位是
/// 码点而非 UTF-16 code unit（例如 emoji 是 1 个码点、2 个 UTF-16 单元）。
fn str_code_points(s : String) -> Int {
  let mut n = 0
  for _c in s {
    n += 1
  }
  n
}
