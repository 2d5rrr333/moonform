///|
/// zod 风格的流式 Schema 构建器。
///
/// 与 zod 一致：`object` 的字段**默认必填**，`.optional()` / `.nullable()`
/// 显式放宽；`.strict()` 拒绝多余字段（对应 `additionalProperties: false`）。
///
/// 两个出口：
/// - `.compile()`：生成 moonschema 校验器（builder 层自动开启 format 断言）
/// - `.to_schema()`：降级为标准 JSON Schema 2020-12 文档，可与任何语言互通
pub struct SchemaBuilder {
  kw : Map[String, Json]
  main_type : String?
  mut item : SchemaBuilder?
  mut fields : Map[String, SchemaBuilder]?
  mut optional_ : Bool
  mut nullable_ : Bool
  mut strict_ : Bool
  mut catchall_ : SchemaBuilder?
  mut rules_ : Array[String]?
}

///|
fn SchemaBuilder::make(t? : String) -> SchemaBuilder {
  {
    kw: Map([], capacity=8),
    main_type: t,
    item: None,
    fields: None,
    optional_: false,
    nullable_: false,
    strict_: false,
    catchall_: None,
    rules_: None,
  }
}

///|
fn SchemaBuilder::dup(self : SchemaBuilder) -> SchemaBuilder {
  {
    kw: self.kw.copy(),
    main_type: self.main_type,
    item: self.item,
    fields: self.fields,
    optional_: self.optional_,
    nullable_: self.nullable_,
    strict_: self.strict_,
    catchall_: self.catchall_,
    rules_: self.rules_,
  }
}

///|
fn SchemaBuilder::with_kw(
  self : SchemaBuilder,
  key : String,
  value : Json,
) -> SchemaBuilder {
  let b = self.dup()
  b.kw[key] = value
  b
}

///|
/// 字符串类型。别名 `str` 亦可。
pub fn string() -> SchemaBuilder {
  SchemaBuilder::make(t="string")
}

///|
/// `string` 的简短别名。
pub fn str() -> SchemaBuilder {
  SchemaBuilder::make(t="string")
}

///|
/// 双精度数值类型（JSON `number`）。
pub fn number() -> SchemaBuilder {
  SchemaBuilder::make(t="number")
}

///|
/// 整数类型（JSON `number` 且无小数部分）。
pub fn integer() -> SchemaBuilder {
  SchemaBuilder::make(t="integer")
}

///|
/// `integer` 的简短别名。
pub fn int() -> SchemaBuilder {
  SchemaBuilder::make(t="integer")
}

///|
/// 布尔类型。
pub fn boolean() -> SchemaBuilder {
  SchemaBuilder::make(t="boolean")
}

///|
/// null 类型（对应 zod 的 `z.null()`）。
pub fn nil() -> SchemaBuilder {
  SchemaBuilder::make(t="null")
}

///|
/// 任意值（空模式，对应 zod 的 `z.any()`）。
pub fn any() -> SchemaBuilder {
  SchemaBuilder::make()
}

///|
/// 数组类型，元素模式由 `item` 给出（对应 zod 的 `z.array(el)`）。
pub fn array(item : SchemaBuilder) -> SchemaBuilder {
  let b = SchemaBuilder::make(t="array")
  b.item = Some(item)
  b
}

///|
/// 对象类型。**字段默认必填**，与 zod 一致；需要可选时在字段上调用
/// `.optional()`。
pub fn object(fields : Map[String, SchemaBuilder]) -> SchemaBuilder {
  let b = SchemaBuilder::make(t="object")
  b.fields = Some(fields)
  b
}

///|
/// 枚举：值必须等于给定值之一（对应 zod 的 `z.enum([...])`）。
pub fn enum_(values : Array[Json]) -> SchemaBuilder {
  SchemaBuilder::make().with_kw("enum", Json::array(values))
}

///|
/// 字面量：值必须等于常量（对应 zod 的 `z.literal(...)`）。
pub fn literal(value : Json) -> SchemaBuilder {
  SchemaBuilder::make().with_kw("const", value)
}

///|
/// 标记字段可选（仅作为 object 字段时有意义）。
pub fn SchemaBuilder::optional(self : SchemaBuilder) -> SchemaBuilder {
  let b = self.dup()
  b.optional_ = true
  b
}

///|
/// 允许 null（`type` 变为 `[T, "null"]`，对应 zod 的 `.nullable()`）。
pub fn SchemaBuilder::nullable(self : SchemaBuilder) -> SchemaBuilder {
  let b = self.dup()
  b.nullable_ = true
  b
}

///|
/// 字符串最小长度（对应 zod 的 `.min(n)`）。
pub fn SchemaBuilder::min_len(self : SchemaBuilder, n : Int) -> SchemaBuilder {
  self.with_kw("minLength", Json::number(n.to_double()))
}

///|
/// 字符串最大长度（对应 zod 的 `.max(n)`）。
pub fn SchemaBuilder::max_len(self : SchemaBuilder, n : Int) -> SchemaBuilder {
  self.with_kw("maxLength", Json::number(n.to_double()))
}

///|
/// email 格式断言（builder 层默认开启 format 断言，对应 zod 的 `.email()`）。
pub fn SchemaBuilder::email(self : SchemaBuilder) -> SchemaBuilder {
  self.with_kw("format", Json::string("email"))
}

///|
/// UUID 格式断言。
pub fn SchemaBuilder::uuid(self : SchemaBuilder) -> SchemaBuilder {
  self.with_kw("format", Json::string("uuid"))
}

///|
/// IPv4 格式断言。
pub fn SchemaBuilder::ipv4(self : SchemaBuilder) -> SchemaBuilder {
  self.with_kw("format", Json::string("ipv4"))
}

///|
/// 数值下界。
pub fn SchemaBuilder::min(self : SchemaBuilder, n : Double) -> SchemaBuilder {
  self.with_kw("minimum", Json::number(n))
}

///|
/// 数值上界。
pub fn SchemaBuilder::max(self : SchemaBuilder, n : Double) -> SchemaBuilder {
  self.with_kw("maximum", Json::number(n))
}

///|
/// 排他数值下界。
pub fn SchemaBuilder::gt(self : SchemaBuilder, n : Double) -> SchemaBuilder {
  self.with_kw("exclusiveMinimum", Json::number(n))
}

///|
/// 排他数值上界。
pub fn SchemaBuilder::lt(self : SchemaBuilder, n : Double) -> SchemaBuilder {
  self.with_kw("exclusiveMaximum", Json::number(n))
}

///|
/// 数值必须为 n 的倍数。
pub fn SchemaBuilder::multiple_of(
  self : SchemaBuilder,
  n : Double,
) -> SchemaBuilder {
  self.with_kw("multipleOf", Json::number(n))
}

///|
/// 数组最小长度。
pub fn SchemaBuilder::min_items(self : SchemaBuilder, n : Int) -> SchemaBuilder {
  self.with_kw("minItems", Json::number(n.to_double()))
}

///|
/// 数组最大长度。
pub fn SchemaBuilder::max_items(self : SchemaBuilder, n : Int) -> SchemaBuilder {
  self.with_kw("maxItems", Json::number(n.to_double()))
}

///|
/// 要求元素互不相同。
pub fn SchemaBuilder::unique_items(self : SchemaBuilder) -> SchemaBuilder {
  self.with_kw("uniqueItems", Json::boolean(true))
}

///|
/// 拒绝未声明的字段（`additionalProperties: false`，对应 zod 的 `.strict()`）。
pub fn SchemaBuilder::strict(self : SchemaBuilder) -> SchemaBuilder {
  let b = self.dup()
  b.strict_ = true
  b
}

///|
/// 未声明字段的兜底模式（对应 zod 的 `.catchall()`）。
pub fn SchemaBuilder::catchall(
  self : SchemaBuilder,
  fallback : SchemaBuilder,
) -> SchemaBuilder {
  let b = self.dup()
  b.catchall_ = Some(fallback)
  b
}

///|
/// 附加描述（JSON Schema annotation `description`）。
pub fn SchemaBuilder::describe(
  self : SchemaBuilder,
  text : String,
) -> SchemaBuilder {
  self.with_kw("description", Json::string(text))
}

///|
/// 追加一条跨字段动态规则（引擎扩展关键词 `x-rules`）。
///
/// 表达式路径相对声明节点的实例，例如
/// `"end_date > start_date"`、`"items[0].price * items[0].qty == total"`。
/// 表达式引用的路径**全部存在**时才参与判定（缺失即藐视通过），
/// 字段是否必填仍由默认必填 / `.optional()` 表达。
/// 通常作用于 `object(...)` 节点；规则语法错误在 `.compile()` 时即报错。
pub fn SchemaBuilder::satisfy(
  self : SchemaBuilder,
  expr : String,
) -> SchemaBuilder {
  let b = self.dup()
  match b.rules_ {
    Some(rs) => rs.push(expr)
    None => b.rules_ = Some([expr])
  }
  b
}

///|
/// 降级为标准 JSON Schema 2020-12 文档。
pub fn SchemaBuilder::to_schema(self : SchemaBuilder) -> Json {
  let m : Map[String, Json] = Map([], capacity=8)
  match self.main_type {
    Some(t) =>
      if self.nullable_ && t != "null" {
        m["type"] = Json::array([Json::string(t), Json::string("null")])
      } else {
        m["type"] = Json::string(t)
      }
    None => ()
  }
  for k, v in self.kw {
    m[k] = v
  }
  match self.rules_ {
    Some(rs) => m["x-rules"] = Json::array(rs.map(Json::string))
    None => ()
  }
  match self.item {
    Some(it) => m["items"] = it.to_schema()
    None => ()
  }
  match self.fields {
    Some(fields) => {
      let props : Map[String, Json] = Map([], capacity=8)
      let required : Array[Json] = []
      for name, fb in fields {
        props[name] = fb.to_schema()
        if !fb.optional_ {
          required.push(Json::string(name))
        }
      }
      m["properties"] = Json::object(props)
      if required.length() > 0 {
        m["required"] = Json::array(required)
      }
      match self.catchall_ {
        Some(c) => m["additionalProperties"] = c.to_schema()
        None =>
          if self.strict_ {
            m["additionalProperties"] = Json::boolean(false)
          }
      }
    }
    None => ()
  }
  Json::object(m)
}

///|
/// 编译为 moonschema 校验器。builder 层自动开启 format 断言
/// （`.email()` / `.uuid()` / `.ipv4()` 因此真实生效）。
/// `locale` 指定校验错误消息语言（默认英文，中文传 `ZH`）。
pub fn SchemaBuilder::compile(
  self : SchemaBuilder,
  locale? : @schema.Locale = @schema.Locale::EN,
) -> @schema.Schema raise @schema.CompileError {
  @schema.compile(
    self.to_schema(),
    options=@schema.CompileOptions::new(assert_format=true, locale~),
  )
}

///|
/// 便捷入口：解析 JSON 实例文本（配合构建器校验时构造实例用）。
pub fn parse_json(text : String) -> Json raise @json.ParseError {
  @json.parse(text)
}
