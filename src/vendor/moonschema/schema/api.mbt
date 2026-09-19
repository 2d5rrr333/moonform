///|
/// 便捷入口：解析 JSON 文本为 `Json` 值（转发到 `@json.parse`）。
///
/// 让使用者只依赖本包即可完成 "解析 → 编译 → 校验" 全流程。
pub fn parse(text : String) -> Json raise @json.ParseError {
  fix_integer_overflow(@json.parse(text))
}

///|
/// core JSON 解析器的整数路径在 |n| >= 2^53 时误产出 Infinity（上游 bug）。
/// `Number` 保留了原文 repr，这里用 `@string.parse_double`（正确的 IEEE 754
/// 就近舍入）重解析修复，语义与 JS 的 `JSON.parse` 一致。
fn fix_integer_overflow(v : Json) -> Json {
  match v {
    Number(n, repr~) => {
      // 非有限检测：Infinity 满足 n/2 == n 且 n != 0
      let broken = n.is_nan() || (n != 0.0 && n / 2.0 == n)
      if !broken {
        return v
      }
      let s = match repr {
        Some(s) => s
        None => return v
      }
      let fixed : Double? = Some(@string.parse_double(s)) catch { _ => None }
      match fixed {
        Some(d) => Json::number(d, repr=s)
        None => v
      }
    }
    Array(arr) => {
      let out : Array[Json] = []
      for x in arr {
        out.push(fix_integer_overflow(x))
      }
      Json::array(out)
    }
    Object(m) => {
      let out : Map[String, Json] = Map([], capacity=16)
      for k, x in m {
        out[k] = fix_integer_overflow(x)
      }
      Json::object(out)
    }
    other => other
  }
}
