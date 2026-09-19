///|
/// 把路径解析为实例上的值；字段缺失或类型不通时返回 `VMissing`。
fn resolve(root : Json, segs : Array[PathSeg]) -> Value {
  let mut cur : Json? = Some(root)
  for seg in segs {
    let next : Json? = match (cur, seg) {
      (Some(Object(m)), PKey(k)) => m.get(k)
      (Some(Array(a)), PIndex(i)) =>
        if i < a.length() {
          Some(a[i])
        } else {
          None
        }
      _ => None
    }
    cur = next
  }
  match cur {
    Some(Number(x, ..)) => VNum(x)
    Some(String(s)) => VStr(s)
    Some(True) => VBool(true)
    Some(False) => VBool(false)
    Some(Null) => VNull
    _ => VMissing
  }
}

///|
fn eval(e : Expr, root : Json) -> Value {
  match e {
    ENum(d) => VNum(d)
    EStr(s) => VStr(s)
    EBool(b) => VBool(b)
    ENull => VNull
    EPath(segs) => resolve(root, segs)
    ENot(inner) => VBool(!eval(inner, root).truthy())
    EArith(op, l, r) => {
      let lv = eval(l, root)
      let rv = eval(r, root)
      match (lv, rv) {
        (VNum(a), VNum(b)) => {
          let v = match op {
            "+" => a + b
            "-" => a - b
            "*" => a * b
            "/" => a / b
            "%" => a % b
            _ => return VMissing
          }
          // 除零等产生的 Inf/NaN 视为不可满足
          if v.is_nan() || (v != 0.0 && v / 2.0 == v) {
            VMissing
          } else {
            VNum(v)
          }
        }
        _ => VMissing
      }
    }
    ECmp(op, l, r) => {
      let lv = eval(l, root)
      let rv = eval(r, root)
      VBool(compare(op, lv, rv))
    }
    ELogic(op, l, r) => {
      let lt = eval(l, root).truthy()
      if op == "&&" {
        if !lt {
          VBool(false)
        } else {
          VBool(eval(r, root).truthy())
        }
      } else if lt {
        VBool(true)
      } else {
        VBool(eval(r, root).truthy())
      }
    }
  }
}

///|
/// 比较语义：
/// - 任一侧 `VMissing`（毒值）→ 一律为假（包括 `!=`）
/// - `==`/`!=`：同类型按值比较，跨类型为假
/// - `< <= > >=`：两侧同为数值（按数值）或同为字符串（按字典序），否则为假
fn compare(op : String, lv : Value, rv : Value) -> Bool {
  if lv is VMissing || rv is VMissing {
    return false
  }
  match op {
    "==" => value_eq(lv, rv)
    "!=" => !value_eq(lv, rv)
    "<" => order(lv, rv) is Some(lt) && lt < 0
    "<=" => order(lv, rv) is Some(le) && le <= 0
    ">" => order(lv, rv) is Some(gt) && gt > 0
    ">=" => order(lv, rv) is Some(ge) && ge >= 0
    _ => false
  }
}

///|
fn value_eq(lv : Value, rv : Value) -> Bool {
  match (lv, rv) {
    (VNum(a), VNum(b)) => a == b
    (VStr(a), VStr(b)) => a == b
    (VBool(a), VBool(b)) => a == b
    (VNull, VNull) => true
    _ => false
  }
}

///|
/// 同类型可序比较返回 -1/0/1，否则 None。
fn order(lv : Value, rv : Value) -> Int? {
  match (lv, rv) {
    (VNum(a), VNum(b)) =>
      if a < b {
        Some(-1)
      } else if a > b {
        Some(1)
      } else {
        Some(0)
      }
    (VStr(a), VStr(b)) =>
      if a < b {
        Some(-1)
      } else if a > b {
        Some(1)
      } else {
        Some(0)
      }
    _ => None
  }
}

///|
/// 收集表达式引用的全部路径（用于"缺失即藐视通过"的预检查）。
fn collect_paths(e : Expr, out : Array[Array[PathSeg]]) -> Unit {
  match e {
    EPath(segs) => out.push(segs)
    ENot(inner) => collect_paths(inner, out)
    EArith(_, l, r) => {
      collect_paths(l, out)
      collect_paths(r, out)
    }
    ECmp(_, l, r) => {
      collect_paths(l, out)
      collect_paths(r, out)
    }
    ELogic(_, l, r) => {
      collect_paths(l, out)
      collect_paths(r, out)
    }
    _ => ()
  }
}

///|
/// 规则是否成立。
///
/// **缺失即藐视通过**：表达式引用的任一路径在实例上不存在时，规则直接通过
/// （可选项的成对约束只应约束"存在"的场合；字段是否必填由 `required` 表达）。
pub fn rule_holds(e : Expr, root : Json) -> Bool {
  let paths : Array[Array[PathSeg]] = []
  collect_paths(e, paths)
  for segs in paths {
    if resolve(root, segs) is VMissing {
      return true
    }
  }
  eval(e, root) is VBool(true)
}
