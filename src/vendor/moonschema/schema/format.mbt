///|
/// format 断言检查（仅在 `assert_format` 开启时生效）。
/// 返回 `None` 表示引擎不认识该 format——按 2020-12 规范，
/// 未知 format 一律视为 annotation，不断言。
fn check_format(f : String, s : String) -> Bool? {
  match f {
    "email" => Some(is_email(s))
    "uuid" => Some(is_uuid(s))
    "ipv4" => Some(is_ipv4(s))
    _ => None
  }
}

///|
fn is_hex_digit(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// 简化版 email 检查：恰好一个 `@`，两端非空、无空白，domain 至少一个点。
/// （完整的 RFC 5322 语法验证不在 v0 目标内。）
fn is_email(s : String) -> Bool {
  let n = s.length()
  let chars = s.to_array()
  let mut at = -1
  for i in 0..<n {
    let c = chars[i]
    if c == '@' {
      if at >= 0 {
        return false
      }
      at = i
    } else if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      return false
    }
  }
  if at <= 0 || at >= n - 1 {
    return false
  }
  let mut dots = 0
  for i in (at + 1)..<n {
    let c = chars[i]
    if c == '.' {
      dots += 1
    } else if c == ' ' || c == '\t' {
      return false
    }
  }
  dots >= 1 && chars[at + 1] != '.' && chars[n - 1] != '.'
}

///|
fn is_uuid(s : String) -> Bool {
  if s.length() != 36 {
    return false
  }
  let chars = s.to_array()
  for i in 0..<36 {
    let c = chars[i]
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if c != '-' {
        return false
      }
    } else if !is_hex_digit(c) {
      return false
    }
  }
  true
}

///|
fn is_ipv4(s : String) -> Bool {
  let chars = s.to_array()
  let n = chars.length()
  let mut octets = 0
  let mut val = 0
  let mut digits = 0
  for i in 0..<n {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      val = val * 10 + (c.to_int() - '0'.to_int())
      digits += 1
      if digits > 3 || val > 255 {
        return false
      }
    } else if c == '.' {
      if digits == 0 {
        return false
      }
      octets += 1
      val = 0
      digits = 0
    } else {
      return false
    }
  }
  octets == 3 && digits > 0
}
