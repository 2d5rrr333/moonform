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

## wizard — FormGroup 分步表单（组级校验 + 组内提交）

对应 FormGroup 能力：多步表单按步骤分组，每步独立校验/提交，
组错误与分发到子字段的错误并存，最终整表提交以全组有效为门槛。

### 无头验证（headless，本仓库 CI 可跑）

```bash
moon run src/examples/wizard --target js
# → wizard example: all checks passed
```

验证的场景：

1. **双通道组校验**：step1 的组校验器一次返回组级错误（email）+ 分发到子字段的
   错误（username）——`is_group_valid` 与 `is_fields_valid` 各自独立翻转
2. **组内提交不碰表单**：step1 提交成功后 `form.submission_attempts() == 0`；
   step2 提交不改变 step1 的计数
3. **修复后恢复**：修正字段值再提交，组快照（经 `GroupBridge` 读取）恢复
   `is_valid`，分发到字段的错误清除
4. **整表提交门槛**：所有组有效后 `form.handle_submit` 成功

### React 组件接线（浏览器）

组状态经 `GroupBridge` 消费（字段级的 FieldBridge 同理）：

```moonbit
// 组件 setup（每组一次）:
let step1 = form.group(account_l(), on_submit_validate=account_validator())
let bridge = @formreact.GroupBridge::make(step1)

// 组件渲染函数内:
let state = @react.use_sync_external_store(
  notify => { handle.subscribe() ... },   // GroupBridgeHook：前缀订阅（整棵子树）
  () => { handle.get_snapshot() },        // value/errors/is_valid/can_submit...
)
// 提交按钮: bridge.submit(on_group_submit=..., on_group_submit_invalid=...)
```

`GroupBridge` 用**前缀订阅**（`FormApi::subscribe_under`）监听组 key 下所有
变化——分发到子字段的错误、touched 派生都挂在子字段上，整棵子树的任何变化
都会刷新组快照。

## isomorphic —— 一份校验定义，js 客户端 + native 服务端

对应"同构校验复用"场景：`isomorphic`（库）持有唯一的字段校验器定义，
`isomorphic-client`（js）用它做实时反馈，`isomorphic-server`（native）
用同一份定义做服务端最终把关——零序列化损耗、零逻辑重复。

### 无头验证（本仓库 CI 可跑）

```bash
moon run src/examples/isomorphic-client --target js
moon run src/examples/isomorphic-server --target native   # 需 C 编译器（CI 的 ubuntu 有）
# → isomorphic client/server: all checks passed
```

验证的场景：

1. **实时反馈（客户端）**：非法输入逐字段报错、修正即清除、提交通过
2. **最终把关（服务端）**：绕过 UI 的恶意载荷四个字段全部拒绝；
   修正载荷接受；部分非法只报该字段
3. **同构性本身**：`isomorphic` 的黑盒测试在 js/wasm/native 三目标运行
   （CI 三份 test 作业各跑一遍）——同一断言跨目标成立

### 包结构说明

- `core` / `rules`：零依赖（moon.mod 的 `deps` 仅为 react 示例与适配层存在）
- `schema`：moonschema 适配（QuietlyChan/moonschema@0.1.0 源码 vendor 于
  `src/vendor/moonschema`，Apache-2.0；上游未发布 mooncakes）
- `react`：tiye/react 适配器（仅 js 目标）
