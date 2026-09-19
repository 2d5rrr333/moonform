///|
enum Token {
  TNum(Double)
  TStr(String)
  TIdent(String)
  TOp(String)
} derive(Eq)

///|
/// 词法分析：把规则源文本切成 token 序列。
fn tokenize(src : String) -> Array[Token] raise ExprError {
  let toks : Array[Token] = []
  let chars = src.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else if c >= '0' && c <= '9' {
      // 数字字面量：整数 / 小数 / 指数，交给 parse_double 做正确舍入
      let start = i
      while i < n && chars[i] >= '0' && chars[i] <= '9' {
        i += 1
      }
      if i < n && chars[i] == '.' {
        i += 1
        while i < n && chars[i] >= '0' && chars[i] <= '9' {
          i += 1
        }
      }
      if i < n && (chars[i] == 'e' || chars[i] == 'E') {
        i += 1
        if i < n && (chars[i] == '+' || chars[i] == '-') {
          i += 1
        }
        while i < n && chars[i] >= '0' && chars[i] <= '9' {
          i += 1
        }
      }
      let text = src[start:i].to_owned()
      let parsed : Double? = Some(@string.parse_double(text)) catch {
        _ => None
      }
      match parsed {
        Some(d) => toks.push(TNum(d))
        None =>
          raise ExprSyntax(
            "rule syntax error at offset \{i}: invalid number \"\{text}\"",
          )
      }
    } else if c == '"' {
      // 字符串字面量，支持 \" \\ \n \t \r
      i += 1
      let b = StringBuilder()
      let mut closed = false
      while i < n {
        let sc = chars[i]
        if sc == '\\' {
          if i + 1 >= n {
            break
          }
          let esc = chars[i + 1]
          match esc {
            '"' => b.write_char('"')
            '\\' => b.write_char('\\')
            'n' => b.write_char('\n')
            't' => b.write_char('\t')
            'r' => b.write_char('\r')
            _ =>
              raise ExprSyntax(
                "rule syntax error at offset \{i}: invalid escape \"\\\{esc}\"",
              )
          }
          i += 2
        } else if sc == '"' {
          closed = true
          i += 1
          break
        } else {
          b.write_char(sc)
          i += 1
        }
      }
      if !closed {
        raise ExprSyntax(
          "rule syntax error at offset \{i}: unterminated string",
        )
      }
      toks.push(TStr(b.to_string()))
    } else if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
      // 标识符 / 关键字
      let start = i
      while i < n {
        let ic = chars[i]
        if (ic >= 'a' && ic <= 'z') ||
          (ic >= 'A' && ic <= 'Z') ||
          (ic >= '0' && ic <= '9') ||
          ic == '_' {
          i += 1
        } else {
          break
        }
      }
      toks.push(TIdent(src[start:i].to_owned()))
    } else {
      // 运算符：两字符优先
      let two = if i + 1 < n {
        let pair = StringBuilder()
        pair.write_char(c)
        pair.write_char(chars[i + 1])
        pair.to_string()
      } else {
        ""
      }
      if two == "&&" ||
        two == "||" ||
        two == "==" ||
        two == "!=" ||
        two == "<=" ||
        two == ">=" {
        toks.push(TOp(two))
        i += 2
      } else if c == '<' ||
        c == '>' ||
        c == '+' ||
        c == '-' ||
        c == '*' ||
        c == '/' ||
        c == '%' ||
        c == '!' ||
        c == '(' ||
        c == ')' ||
        c == '[' ||
        c == ']' ||
        c == '.' {
        let single = StringBuilder()
        single.write_char(c)
        toks.push(TOp(single.to_string()))
        i += 1
      } else {
        raise ExprSyntax(
          "rule syntax error at offset \{i}: unexpected character \"\{c}\"",
        )
      }
    }
  }
  toks
}
