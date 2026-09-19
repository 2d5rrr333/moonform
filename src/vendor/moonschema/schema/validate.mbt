///|
fn err(
  keyword : String,
  ipath : Array[String],
  spath : Array[String],
  message : String,
) -> ValidationError {
  {
    keyword,
    instance_path: instance_pointer(ipath),
    // ajv 风格：schema_path 以触发错误的关键词名结尾，如 "#/properties/age/minimum"
    schema_path: "\{schema_pointer(spath)}/\{escape_pointer_token(keyword)}",
    message,
  }
}

///|
/// `false schema` 等特殊情况：关键词名不是模式里的路径段。
fn err_no_leaf(
  keyword : String,
  ipath : Array[String],
  spath : Array[String],
  message : String,
) -> ValidationError {
  {
    keyword,
    instance_path: instance_pointer(ipath),
    schema_path: schema_pointer(spath),
    message,
  }
}

///|
/// 属性键是否已被 `properties` / `patternProperties` "评估"——
/// 决定 `additionalProperties` 是否对其生效。
fn key_is_known(kw : Keywords, k : String) -> Bool {
  match kw.properties {
    Some(p) => if p.contains(k) { return true }
    None => ()
  }
  match kw.pattern_properties {
    Some(pairs) =>
      for i in 0..<pairs.length() {
        match pairs[i].0.execute(k) {
          Some(_) => return true
          None => ()
        }
      }
    None => ()
  }
  false
}

///|
fn validate_node(
  root : Schema,
  node : Node,
  v : Json,
  ipath : Array[String],
  spath : Array[String],
  errors : Array[ValidationError],
) -> Bool {
  match node {
    BoolNode(true) => true
    BoolNode(false) => {
      errors.push(
        err_no_leaf(
          "false schema",
          ipath,
          spath,
          tr(
            root.ctx.locale,
            "boolean schema is false",
            "布尔模式为 false",
          ),
        ),
      )
      false
    }
    SchemaNode(kw) => validate_keywords(root, kw, v, ipath, spath, errors)
  }
}

///|
/// `$ref` 惰性解析：首次校验时编译被引用的子模式并缓存，递归模式因此安全。
fn get_or_compile_ref(root : Schema, pointer : String) -> Schema? {
  let ctx = root.ctx
  match ctx.cache.get(pointer) {
    Some(s) => Some(s)
    None =>
      match parse_local_ref(pointer) {
        Some(tokens) =>
          match resolve_pointer(ctx.root, tokens) {
            Some(target) => {
              let spath : Array[String] = ["#"]
              for t in tokens {
                spath.push(t)
              }
              let node : Node? = Some(compile_node(target, ctx, spath)) catch {
                _ => None
              }
              match node {
                Some(n) => {
                  let s : Schema = { node: n, ctx, }
                  ctx.cache[pointer] = s
                  Some(s)
                }
                None => None
              }
            }
            None => None
          }
        None => None
      }
  }
}

///|
fn validate_keywords(
  root : Schema,
  kw : Keywords,
  v : Json,
  ipath : Array[String],
  spath : Array[String],
  errors : Array[ValidationError],
) -> Bool {
  let start_len = errors.length()
  let loc = root.ctx.locale
  // 2020-12：$ref 与其余关键词并存，先验证 ref 目标，再验证本地关键词
  match kw.ref_ {
    Some(r) =>
      match get_or_compile_ref(root, r) {
        Some(s) => {
          let _ = validate_node(root, s.node, v, ipath, spath, errors)
        }
        None =>
          errors.push(
            err(
              "$ref",
              ipath,
              spath,
              tr(
                loc,
                "cannot resolve $ref \"\{r}\"",
                "无法解析 $ref \"\{r}\"",
              ),
            ),
          )
      }
    None => ()
  }
  match kw.typ {
    Some(ts) => {
      let mut ok = false
      for i in 0..<ts.length() {
        if v.matches_type(ts[i]) {
          ok = true
        }
      }
      if !ok {
        let b = StringBuilder()
        for i in 0..<ts.length() {
          if i > 0 {
            if i == ts.length() - 1 {
              b.write_string(" or ")
            } else {
              b.write_string(", ")
            }
          }
          b.write_string(ts[i].label())
        }
        errors.push(
          err(
            "type",
            ipath,
            spath,
            tr(loc, "must be \{b.to_string()}", "必须是 \{b.to_string()}"),
          ),
        )
      }
    }
    None => ()
  }
  match kw.const_ {
    Some(c) =>
      if !json_eq(v, c) {
        errors.push(
          err(
            "const",
            ipath,
            spath,
            tr(loc, "must be equal to constant", "必须等于常量值"),
          ),
        )
      }
    None => ()
  }
  match kw.enum_ {
    Some(vals) => {
      let mut ok = false
      for i in 0..<vals.length() {
        if json_eq(v, vals[i]) {
          ok = true
        }
      }
      if !ok {
        errors.push(
          err(
            "enum",
            ipath,
            spath,
            tr(
              loc, "must be equal to one of the allowed values", "必须是允许的枚举值之一",
            ),
          ),
        )
      }
    }
    None => ()
  }
  if v is Number(n, ..) {
    match kw.multiple_of {
      Some(m) => {
        // 浮点求余对 0.0075 % 0.0001 这类十进制场景有精度噪声，
        // 改用商到最近整数的相对容差判定（与主流实现一致的工程取舍）
        let q = n / m
        let frac = q - q.floor()
        let mag = if q.abs() > 1.0 { q.abs() } else { 1.0 }
        let eps = 1.0e-9 * mag
        if !(frac == 0.0 || frac < eps || 1.0 - frac < eps) {
          errors.push(
            err(
              "multipleOf",
              ipath,
              spath,
              tr(loc, "must be multiple of \{m}", "必须是 \{m} 的倍数"),
            ),
          )
        }
      }
      None => ()
    }
    match kw.maximum {
      Some(m) =>
        if n > m {
          errors.push(
            err(
              "maximum",
              ipath,
              spath,
              tr(loc, "must be <= \{m}", "必须 <= \{m}"),
            ),
          )
        }
      None => ()
    }
    match kw.exclusive_maximum {
      Some(m) =>
        if n >= m {
          errors.push(
            err(
              "exclusiveMaximum",
              ipath,
              spath,
              tr(loc, "must be < \{m}", "必须 < \{m}"),
            ),
          )
        }
      None => ()
    }
    match kw.minimum {
      Some(m) =>
        if n < m {
          errors.push(
            err(
              "minimum",
              ipath,
              spath,
              tr(loc, "must be >= \{m}", "必须 >= \{m}"),
            ),
          )
        }
      None => ()
    }
    match kw.exclusive_minimum {
      Some(m) =>
        if n <= m {
          errors.push(
            err(
              "exclusiveMinimum",
              ipath,
              spath,
              tr(loc, "must be > \{m}", "必须 > \{m}"),
            ),
          )
        }
      None => ()
    }
  }
  if v is String(sv) {
    match kw.min_length {
      Some(ml) =>
        if str_code_points(sv) < ml {
          errors.push(
            err(
              "minLength",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have fewer than \{ml} characters",
                "字符数不能少于 \{ml}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.max_length {
      Some(ml) =>
        if str_code_points(sv) > ml {
          errors.push(
            err(
              "maxLength",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have more than \{ml} characters",
                "字符数不能超过 \{ml}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.format {
      Some(f) =>
        if root.ctx.assert_format {
          match check_format(f, sv) {
            Some(false) =>
              errors.push(
                err(
                  "format",
                  ipath,
                  spath,
                  tr(
                    loc,
                    "must match format \"\{f}\"",
                    "必须符合格式 \"\{f}\"",
                  ),
                ),
              )
            _ => ()
          }
        }
      None => ()
    }
    match kw.pattern {
      Some((re, src)) =>
        match re.execute(sv) {
          Some(_) => ()
          None =>
            errors.push(
              err(
                "pattern",
                ipath,
                spath,
                tr(
                  loc,
                  "must match pattern \"\{src}\"",
                  "必须匹配模式 \"\{src}\"",
                ),
              ),
            )
        }
      None => ()
    }
  }
  if v is Array(arr) {
    match kw.min_items {
      Some(m) =>
        if arr.length() < m {
          errors.push(
            err(
              "minItems",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have fewer than \{m} items",
                "元素个数不能少于 \{m}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.max_items {
      Some(m) =>
        if arr.length() > m {
          errors.push(
            err(
              "maxItems",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have more than \{m} items",
                "元素个数不能超过 \{m}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.unique_items {
      Some(true) => {
        let n = arr.length()
        let mut dup_found = false
        let mut i = 0
        while i < n {
          if dup_found {
            break
          }
          let mut j = 0
          while j < i {
            if json_eq(arr[i], arr[j]) {
              dup_found = true
              break
            }
            j += 1
          }
          i += 1
        }
        if dup_found {
          errors.push(
            err(
              "uniqueItems",
              ipath,
              spath,
              tr(
                loc, "must NOT have duplicate items", "不能包含重复元素",
              ),
            ),
          )
        }
      }
      _ => ()
    }
    // 2020-12：prefixItems 约束前缀，items 约束其余元素
    let pcount = match kw.prefix_items {
      Some(p) => p.length()
      None => 0
    }
    for i in 0..<arr.length() {
      ipath.push(i.to_string())
      if i < pcount {
        let p = kw.prefix_items.unwrap()[i]
        spath.push("prefixItems")
        spath.push(i.to_string())
        let _ = validate_node(root, p.node, arr[i], ipath, spath, errors)
        ignore(spath.pop())
        ignore(spath.pop())
      } else {
        match kw.items {
          Some(it) => {
            spath.push("items")
            let _ = validate_node(root, it.node, arr[i], ipath, spath, errors)
            ignore(spath.pop())
          }
          None => ()
        }
      }
      ignore(ipath.pop())
    }
    match kw.contains {
      Some(cs) => {
        let min_c = kw.min_contains.unwrap_or(1)
        let mut count = 0
        for i in 0..<arr.length() {
          let sub : Array[ValidationError] = []
          ipath.push(i.to_string())
          spath.push("contains")
          let ok = validate_node(root, cs.node, arr[i], ipath, spath, sub)
          ignore(spath.pop())
          ignore(ipath.pop())
          if ok {
            count += 1
          }
        }
        if count < min_c {
          errors.push(
            err(
              "contains",
              ipath,
              spath,
              tr(
                loc,
                "must contain at least \{min_c} valid item(s)",
                "至少包含 \{min_c} 个匹配 contains 的元素",
              ),
            ),
          )
        }
        match kw.max_contains {
          Some(mc) =>
            if count > mc {
              errors.push(
                err(
                  "maxContains",
                  ipath,
                  spath,
                  tr(
                    loc,
                    "must contain no more than \{mc} valid item(s)",
                    "匹配 contains 的元素不能超过 \{mc} 个",
                  ),
                ),
              )
            }
          None => ()
        }
      }
      None => ()
    }
  }
  if v is Object(obj) {
    match kw.min_properties {
      Some(m) =>
        if obj.length() < m {
          errors.push(
            err(
              "minProperties",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have fewer than \{m} properties",
                "属性个数不能少于 \{m}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.max_properties {
      Some(m) =>
        if obj.length() > m {
          errors.push(
            err(
              "maxProperties",
              ipath,
              spath,
              tr(
                loc,
                "must NOT have more than \{m} properties",
                "属性个数不能超过 \{m}",
              ),
            ),
          )
        }
      None => ()
    }
    match kw.required {
      Some(req) =>
        for i in 0..<req.length() {
          let p = req[i]
          if !obj.contains(p) {
            errors.push(
              err(
                "required",
                ipath,
                spath,
                tr(
                  loc,
                  "must have required property \"\{p}\"",
                  "缺少必需属性 \"\{p}\"",
                ),
              ),
            )
          }
        }
      None => ()
    }
    match kw.properties {
      Some(props) =>
        for k, sub in props {
          match obj.get(k) {
            Some(pv) => {
              ipath.push(k)
              spath.push("properties")
              spath.push(k)
              let _ = validate_node(root, sub.node, pv, ipath, spath, errors)
              ignore(spath.pop())
              ignore(spath.pop())
              ignore(ipath.pop())
            }
            None => ()
          }
        }
      None => ()
    }
    // patternProperties：键名匹配正则的每个值都要通过对应模式
    match kw.pattern_properties {
      Some(pairs) =>
        for k, ov in obj {
          for i in 0..<pairs.length() {
            let pair = pairs[i]
            match pair.0.execute(k) {
              Some(_) => {
                ipath.push(k)
                spath.push("patternProperties")
                spath.push(pair.1)
                let _ = validate_node(
                  root,
                  pair.2.node,
                  ov,
                  ipath,
                  spath,
                  errors,
                )
                ignore(spath.pop())
                ignore(spath.pop())
                ignore(ipath.pop())
              }
              None => ()
            }
          }
        }
      None => ()
    }
    match kw.additional_closed {
      Some(true) =>
        for k, _ov in obj {
          if !key_is_known(kw, k) {
            errors.push(
              err(
                "additionalProperties",
                ipath,
                spath,
                tr(
                  loc,
                  "must NOT have additional properties (\"\{k}\")",
                  "不允许出现多余属性 (\"\{k}\")",
                ),
              ),
            )
          }
        }
      _ => ()
    }
    match kw.additional {
      Some(add) =>
        for k, ov in obj {
          if !key_is_known(kw, k) {
            ipath.push(k)
            spath.push("additionalProperties")
            let _ = validate_node(root, add.node, ov, ipath, spath, errors)
            ignore(spath.pop())
            ignore(ipath.pop())
          }
        }
      None => ()
    }
    match kw.property_names {
      Some(pn) =>
        for k, _ov in obj {
          ipath.push(k)
          spath.push("propertyNames")
          let _ = validate_node(
            root,
            pn.node,
            Json::string(k),
            ipath,
            spath,
            errors,
          )
          ignore(spath.pop())
          ignore(ipath.pop())
        }
      None => ()
    }
    match kw.dependent_required {
      Some(m) =>
        for k, deps in m {
          if obj.contains(k) {
            for i in 0..<deps.length() {
              let d = deps[i]
              if !obj.contains(d) {
                errors.push(
                  err(
                    "dependentRequired",
                    ipath,
                    spath,
                    tr(
                      loc,
                      "must have property \"\{d}\" when property \"\{k}\" is present",
                      "存在属性 \"\{k}\" 时必须同时提供 \"\{d}\"",
                    ),
                  ),
                )
              }
            }
          }
        }
      None => ()
    }
    match kw.dependent_schemas {
      Some(m) =>
        for k, ds in m {
          if obj.contains(k) {
            spath.push("dependentSchemas")
            spath.push(k)
            let _ = validate_node(root, ds.node, v, ipath, spath, errors)
            ignore(spath.pop())
            ignore(spath.pop())
          }
        }
      None => ()
    }
  }
  match kw.all_of {
    Some(list) =>
      for i in 0..<list.length() {
        spath.push("allOf")
        spath.push(i.to_string())
        let _ = validate_node(root, list[i].node, v, ipath, spath, errors)
        ignore(spath.pop())
        ignore(spath.pop())
      }
    None => ()
  }
  match kw.any_of {
    Some(list) => {
      let mut matched = false
      for i in 0..<list.length() {
        let sub : Array[ValidationError] = []
        spath.push("anyOf")
        spath.push(i.to_string())
        let ok = validate_node(root, list[i].node, v, ipath, spath, sub)
        ignore(spath.pop())
        ignore(spath.pop())
        if ok {
          matched = true
        }
      }
      if !matched {
        errors.push(
          err(
            "anyOf",
            ipath,
            spath,
            tr(
              loc, "must match a schema in anyOf", "必须匹配 anyOf 中的至少一个模式",
            ),
          ),
        )
      }
    }
    None => ()
  }
  match kw.one_of {
    Some(list) => {
      let mut pass_count = 0
      for i in 0..<list.length() {
        let sub : Array[ValidationError] = []
        spath.push("oneOf")
        spath.push(i.to_string())
        let ok = validate_node(root, list[i].node, v, ipath, spath, sub)
        ignore(spath.pop())
        ignore(spath.pop())
        if ok {
          pass_count += 1
        }
      }
      if !(pass_count == 1) {
        errors.push(
          err(
            "oneOf",
            ipath,
            spath,
            tr(
              loc,
              "must match exactly one schema in oneOf (matched \{pass_count})",
              "必须且只能匹配 oneOf 中的一个模式（实际匹配 \{pass_count} 个）",
            ),
          ),
        )
      }
    }
    None => ()
  }
  match kw.not_ {
    Some(n) => {
      let sub : Array[ValidationError] = []
      spath.push("not")
      let ok = validate_node(root, n.node, v, ipath, spath, sub)
      ignore(spath.pop())
      if ok {
        errors.push(
          err(
            "not",
            ipath,
            spath,
            tr(loc, "must NOT be valid", "不能匹配 not 模式"),
          ),
        )
      }
    }
    None => ()
  }
  match kw.if_ {
    Some(i) => {
      let sub : Array[ValidationError] = []
      spath.push("if")
      let ok = validate_node(root, i.node, v, ipath, spath, sub)
      ignore(spath.pop())
      if ok {
        match kw.then_ {
          Some(t) => {
            spath.push("then")
            let _ = validate_node(root, t.node, v, ipath, spath, errors)
            ignore(spath.pop())
          }
          None => ()
        }
      } else {
        match kw.else_ {
          Some(e) => {
            spath.push("else")
            let _ = validate_node(root, e.node, v, ipath, spath, errors)
            ignore(spath.pop())
          }
          None => ()
        }
      }
    }
    None => ()
  }
  // 跨字段动态规则（x-rules）：在其余关键词之后判定
  match kw.rules {
    Some(exprs) =>
      match kw.rule_srcs {
        Some(srcs) =>
          for i in 0..<exprs.length() {
            if !@rules.rule_holds(exprs[i], v) {
              spath.push("x-rules")
              spath.push(i.to_string())
              errors.push(
                err_no_leaf(
                  "x-rules",
                  ipath,
                  spath,
                  tr(
                    loc,
                    "rule \"\{srcs[i]}\" is not satisfied",
                    "规则 \"\{srcs[i]}\" 未满足",
                  ),
                ),
              )
              ignore(spath.pop())
              ignore(spath.pop())
            }
          }
        None => ()
      }
    None => ()
  }
  errors.length() == start_len
}
