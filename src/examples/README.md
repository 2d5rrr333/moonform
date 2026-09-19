# moonform examples

## login — tiye/react 适配器 + moonschema 校验的登录表单

对应验收 2：React 适配器 + moonschema 校验的登录表单（email/password），含实时校验与提交流程。

### 无头验证（headless，本仓库 CI 可跑）

```bash
moon run src/examples/login --target js
# → login example: all checks passed
```

验证的场景（adapters spec）：

1. **输入驱动状态更新**：`FieldBridge::set_value` 写入核心，字段值与 touched/dirty 更新
2. **实时校验**：moonschema（zod-style builder）编译的 schema 经 `schema_field_validator`
   按 JSON-Pointer 路径分发到 email/password 各自的错误槽
3. **错误呈现**：`bridge.state().errors` 非空（非法 email / 短密码）
4. **提交流程**：校验失败 → `on_submit_invalid` 拦截；修正后 → `on_submit` 成功、
   `is_submit_successful == true`

### React 组件接线（浏览器）

组件侧通过 tiye/react 的 `use_sync_external_store` 消费 FieldBridge：

```moonbit
// 组件 setup（每字段一次）:
let form = build_form()                        // 或经 context 注入
let email_bridge = @formreact.FieldBridge::make(form, email_l())
let handle = @formreact.use_field_handle(email_bridge)

// 组件渲染函数内:
let state = @react.use_sync_external_store(
  notify => { handle.subscribe() ... },       // 稳定订阅 → 卸载回调
  () => { handle.get_snapshot() },            // Object.is 稳定快照
)
@react.input(
  value=state.value,
  on_change=fn(v) { email_bridge.set_value(v) }, // 受控输入必须接线 on_change
  [],
)
// 错误呈现: state.errors
```

浏览器运行需要宿主页面提供 `globalThis.React / ReactDOM / ReactDOMClient`
（tiye/react 契约），参考
[tiye/react README](https://mooncakes.io/docs/#/tiye/react/)。

### 包结构说明

- `core` / `rules`：零依赖（moon.mod 的 `deps` 仅为 react 示例与适配层存在）
- `schema`：moonschema 适配（QuietlyChan/moonschema@0.1.0 源码 vendor 于
  `src/vendor/moonschema`，Apache-2.0；上游未发布 mooncakes）
- `react`：tiye/react 适配器（仅 js 目标）
