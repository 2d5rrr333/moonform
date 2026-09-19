///|
/// 递归下降解析器（见 expr.mbt 中的文法）。
priv struct Parser {
  toks : Array[Token]
  mut pos : Int
  src : String
}

///|
fn Parser::peek(self : Parser) -> Token? {
  self.toks.get(self.pos)
}

///|
fn Parser::next(self : Parser) -> Token? {
  let t = self.toks.get(self.pos)
  if t is Some(_) {
    self.pos += 1
  }
  t
}

///|
fn Parser::err(self : Parser, what : String) -> ExprError {
  ExprSyntax(
    "rule syntax error at offset \{self.pos}/\{self.src.length()} in \"\{self.src}\": \{what}",
  )
}

///|
fn Parser::expect_op(self : Parser, op : String) -> Unit raise ExprError {
  guard self.peek() is Some(TOp(actual)) && actual == op else {
    raise self.err("expected \"\{op}\"")
  }
  self.pos += 1
}

///|
fn Parser::is_op(self : Parser, op : String) -> Bool {
  match self.peek() {
    Some(TOp(actual)) => actual == op
    _ => false
  }
}

///|
/// 编译规则表达式；语法错误在编译期暴露（fail fast，与 strict 模式同哲学）。
pub fn compile_expr(src : String) -> Expr raise ExprError {
  let p : Parser = { toks: tokenize(src), pos: 0, src, }
  let e = p.parse_or()
  if !(p.peek() is None) {
    raise p.err("unexpected trailing tokens")
  }
  e
}

///|
fn Parser::parse_or(self : Parser) -> Expr raise ExprError {
  let mut left = self.parse_and()
  while self.is_op("||") {
    ignore(self.next())
    let right = self.parse_and()
    left = ELogic("||", left, right)
  }
  left
}

///|
fn Parser::parse_and(self : Parser) -> Expr raise ExprError {
  let mut left = self.parse_not()
  while self.is_op("&&") {
    ignore(self.next())
    let right = self.parse_not()
    left = ELogic("&&", left, right)
  }
  left
}

///|
fn Parser::parse_not(self : Parser) -> Expr raise ExprError {
  if self.is_op("!") {
    ignore(self.next())
    return ENot(self.parse_not())
  }
  self.parse_cmp()
}

///|
fn Parser::parse_cmp(self : Parser) -> Expr raise ExprError {
  let left = self.parse_add()
  match self.peek() {
    Some(TOp(op)) =>
      if op == "==" ||
        op == "!=" ||
        op == "<" ||
        op == "<=" ||
        op == ">" ||
        op == ">=" {
        ignore(self.next())
        let right = self.parse_add()
        return ECmp(op, left, right)
      }
    _ => ()
  }
  left
}

///|
fn Parser::parse_add(self : Parser) -> Expr raise ExprError {
  let mut left = self.parse_mul()
  let mut looping = true
  while looping {
    if self.is_op("+") {
      ignore(self.next())
      left = EArith("+", left, self.parse_mul())
    } else if self.is_op("-") {
      ignore(self.next())
      left = EArith("-", left, self.parse_mul())
    } else {
      looping = false
    }
  }
  left
}

///|
fn Parser::parse_mul(self : Parser) -> Expr raise ExprError {
  let mut left = self.parse_unary()
  let mut looping = true
  while looping {
    if self.is_op("*") {
      ignore(self.next())
      left = EArith("*", left, self.parse_unary())
    } else if self.is_op("/") {
      ignore(self.next())
      left = EArith("/", left, self.parse_unary())
    } else if self.is_op("%") {
      ignore(self.next())
      left = EArith("%", left, self.parse_unary())
    } else {
      looping = false
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Expr raise ExprError {
  if self.is_op("-") {
    ignore(self.next())
    return EArith("-", ENum(0.0), self.parse_unary())
  }
  self.parse_primary()
}

///|
fn Parser::parse_primary(self : Parser) -> Expr raise ExprError {
  match self.next() {
    Some(TNum(d)) => ENum(d)
    Some(TStr(s)) => EStr(s)
    Some(TIdent(name)) =>
      match name {
        "true" => EBool(true)
        "false" => EBool(false)
        "null" => ENull
        _ => {
          // 路径：ident ("." ident | "[" int "]")*
          let segs : Array[PathSeg] = [PKey(name)]
          let mut walking = true
          while walking {
            if self.is_op(".") {
              ignore(self.next())
              match self.next() {
                Some(TIdent(key)) => segs.push(PKey(key))
                _ => raise self.err("expected identifier after \".\"")
              }
            } else if self.is_op("[") {
              ignore(self.next())
              match self.next() {
                Some(TNum(d)) => {
                  if !(d >= 0.0 && d == d.floor() && d < 1.0e9) {
                    raise self.err(
                      "array index must be a small non-negative integer",
                    )
                  }
                  segs.push(PIndex(d.to_int()))
                }
                _ => raise self.err("expected array index inside \"[\"")
              }
              self.expect_op("]")
            } else {
              walking = false
            }
          }
          EPath(segs)
        }
      }
    Some(TOp("(")) => {
      let e = self.parse_or()
      self.expect_op(")")
      e
    }
    _ => raise self.err("expected expression")
  }
}
