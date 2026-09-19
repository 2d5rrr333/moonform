///|
/// JSON Pointer（RFC 6901）token 转义：`~` → `~0`，`/` → `~1`。
fn escape_pointer_token(t : String) -> String {
  let b = StringBuilder()
  for c in t {
    if c == '~' {
      b.write_string("~0")
    } else if c == '/' {
      b.write_string("~1")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn unescape_pointer_token(t : String) -> String {
  let b = StringBuilder()
  let mut pending_escape = false
  for c in t {
    if pending_escape {
      if c == '0' {
        b.write_char('~')
      } else if c == '1' {
        b.write_char('/')
      } else {
        // 非法转义，宽容处理
        b.write_char(c)
      }
      pending_escape = false
    } else if c == '~' {
      pending_escape = true
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// 实例路径渲染为 JSON Pointer；根为空字符串。
fn instance_pointer(path : Array[String]) -> String {
  let b = StringBuilder()
  for t in path {
    b.write_string("/")
    b.write_string(escape_pointer_token(t))
  }
  b.to_string()
}

///|
/// 模式路径渲染为以 `#` 开头的 JSON Pointer 形式。
fn schema_pointer(path : Array[String]) -> String {
  let b = StringBuilder()
  for i in 0..<path.length() {
    if i == 0 {
      b.write_string(path[0])
    } else {
      b.write_string("/")
      b.write_string(escape_pointer_token(path[i]))
    }
  }
  b.to_string()
}

///|
/// 解析本地 `$ref` 目标（`"#"` 或 `"#/a/b"`），返回去掉 `#` 的 token 列表。
/// token 依次做百分号解码（URI 层）与 `~0`/`~1` 解码（pointer 层）。
/// 命名 fragment（如 `#foo`，即 `$anchor` 引用）不是 JSON Pointer，返回 `None`。
fn parse_local_ref(pointer : String) -> Array[String]? {
  if pointer == "#" {
    return Some([])
  }
  let chars = pointer.to_array()
  if chars.length() < 2 || chars[0] != '#' || chars[1] != '/' {
    return None
  }
  let tokens : Array[String] = []
  let cur = StringBuilder()
  let mut i = 2
  while i < chars.length() {
    let c = chars[i]
    if c == '/' {
      tokens.push(unescape_pointer_token(percent_decode(cur.to_string())))
      cur.reset()
    } else {
      cur.write_char(c)
    }
    i += 1
  }
  tokens.push(unescape_pointer_token(percent_decode(cur.to_string())))
  Some(tokens)
}

///|
fn hex_val(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// URI fragment 的百分号解码（`%25` -> `%` 等）。
/// 仅处理 ASCII 范围的字节，非法序列原样保留。
fn percent_decode(t : String) -> String {
  let chars = t.to_array()
  let b = StringBuilder()
  let mut i = 0
  let n = chars.length()
  while i < n {
    let c = chars[i]
    if c == '%' && i + 2 < n {
      let h = hex_val(chars[i + 1])
      let l = hex_val(chars[i + 2])
      match (h, l) {
        (Some(hh), Some(ll)) =>
          match (hh * 16 + ll).to_char() {
            Some(decoded) => {
              b.write_char(decoded)
              i += 3
            }
            None => {
              b.write_char(c)
              i += 1
            }
          }
        _ => {
          b.write_char(c)
          i += 1
        }
      }
    } else {
      b.write_char(c)
      i += 1
    }
  }
  b.to_string()
}

///|
fn parse_pointer_index(s : String) -> Int? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  if chars.length() > 1 && chars[0] == '0' {
    // 规范要求数组索引不允许前导零
    return None
  }
  let mut v = 0
  for i in 0..<chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
    if v > 100000000 {
      return None
    }
  }
  Some(v)
}

///|
/// 按 token 列表在文档中取值。token 已在 `parse_local_ref` 中解码完毕。
fn resolve_pointer(root : Json, tokens : Array[String]) -> Json? {
  let mut cur : Json? = Some(root)
  for key in tokens {
    let next : Json? = match cur {
      Some(Object(m)) => m.get(key)
      Some(Array(a)) =>
        match parse_pointer_index(key) {
          Some(i) => if i < a.length() { Some(a[i]) } else { None }
          None => None
        }
      _ => None
    }
    cur = next
  }
  cur
}
