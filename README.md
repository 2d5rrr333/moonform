# moonform

MoonBit 原生 headless 表单状态库。**Architecture inspired by [TanStack Form](https://github.com/TanStack/form)**（MIT）。

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/2d5rrr333/moonform/actions/workflows/ci.yml/badge.svg)](https://github.com/2d5rrr333/moonform/actions/workflows/ci.yml)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-2d5rrr333%2Fmoonform-orange)](https://mooncakes.io/docs/#/2d5rrr333/moonform/)

[English](README.en.md) | 中文

## 安装

```bash
# 核心包 + 内置规则（零第三方依赖）
moon add 2d5rrr333/moonform/core
moon add 2d5rrr333/moonform/rules
```

```toml
# moon.mod 中出现（以当前最新版本为准）：
import {
  "2d5rrr333/moonform@0.8.2",
}
```

```toml
# 按需在包的 moon.pkg 中引入：
import {
  "2d5rrr333/moonform/core",
  "2d5rrr333/moonform/rules",
}
```

可选包：`/schema`（moonschema 适配，模块内已含 vendor 源码，无需额外依赖）、`/react`（需 `moon add tiye/react`）、`/lens-gen`（访问器生成器）。

## 是什么

**为什么**：mooncakes.io 已有渲染层（tiye/react 等）与校验层（moonschema 等），但表单状态编排层完全空缺——字段状态机、校验时序（防抖/竞态）、数组字段操作、提交生命周期，是每个 Web 项目都要手写的易错胶水代码。moonform 补齐这一层：headless（不绑定渲染框架）、三目标同构（同一校验定义前端/服务端复用）、行为正确性以上游测试集等价翻译为规格（不是自夸，可审计）。

- **Headless 表单状态机**：字段值、dirty/touched、错误派生、按需订阅、提交编排——语义对标 `@tanstack/form-core@1.33.5`（上游测试集行为等价翻译，见 [upstream/PARITY.md](upstream/PARITY.md)）
- **结构化字段访问器（lens）**：替代 dot-path 字符串——`(key, get, set)` 三元组组合子，编译期安全、重构改名不失配；数组字段操作（push/insert/remove/swap/move/replace）+ meta 迁移
- **字段组（FormGroup）**：以 lens 为前缀的字段分组——组级校验器（组错误 + 错误分发到子字段，未挂载字段延迟浮现）、组内提交（不触碰表单提交态）、form 级 onChange/onChangeGroup 监听器（独立防抖）
- **Resolver 协议**：校验器即插即用——内置轻量规则包（required/min/max/pattern/闭包）+ moonschema（zod-style JSON Schema）适配；schema 可作字段校验器（`schema_field_validator`）或**组校验器**（`schema_group_validator`，错误按组内相对路径分发给子字段）
- **Adapter 协议**：核心不渲染；tiye/react 适配器经 `use_sync_external_store` 桥接
- **跨目标**：core/rules 零第三方依赖，js/wasm/native 三目标可编译；同一校验定义服务端/前端复用（同构）
- **虚拟时钟**：防抖/竞态中止/异步提交对注入的 `Clock` 协议实现——测试确定性推进虚拟时间，不依赖真实定时器

## 包结构

| 包 | 依赖 | 说明 |
|---|---|---|
| `core` | 零 | 状态机、Key/Lens、MetaStore、订阅、Clock、Validator、FormGroup、提交编排 |
| `rules` | 零 | required/min/max/length/pattern/contains/equals/one_of/non_blank/numeric/must_be_true/自定义闭包 |
| `schema` | vendor moonschema | moonschema 适配（JSON-Pointer 错误路径 → 字段错误槽） |
| `react` | tiye/react | FieldBridge + use_field、GroupBridge + use_group、FormBridge + use_form、real_clock 宿主时钟（js 目标） |
| `lens-gen` | 零 | .mbti 驱动的访问器生成器 + CLI（`moon run src/lens-gen-cli -- <pkg.mbti> -o <out.mbt>`） |
| `examples/login` | 全部 | 登录表单示例（headless 验证可跑） |
| `examples/wizard` | 全部 | FormGroup 分步表单示例（headless 验证可跑） |
| `examples/isomorphic` | 全部 | 同构校验：js 客户端实时反馈 + native 服务端把关（CI 双目标跑） |

## 快速开始

```moonbit
struct Login {
  email : String
  password : String
} derive(Eq, Debug)

fn email_l() -> @core.Lens[Login, String] {
  @core.field("email", v => v.email, (v, e) => { ..v, email: e })
}

let form = @core.FormApi::make({ email: "", password: "" })
let email = form.field(
  email_l(),
  on_change_validate=@rules.required().then(@rules.min_length(3)),
)
email.mount()
email.set_value("ab")            // → errors: ["Must be at least 3 characters"]
email.handle_blur()              // → touched + blurred
form.handle_submit(submit_options=...) // 校验拦截 / 提交生命周期
```

数组字段：

```moonbit
// fn friends_l() -> Lens[Form, Array[Friend]] —— 访问器定义同上
form.push_value(friends_l(), friend)
form.remove_value(friends_l(), 0)  // friends[1].name 的错误迁移到 friends[0].name
form.swap_values(friends_l(), 0, 2)
```

异步校验（虚拟时钟，测试确定性）：

```moonbit
let clock = @core.VirtualClock::make()
let form = @core.FormApi::make(values).with_clock(clock.clock())
let field = form.field(
  email_l(),
  on_change_async_debounce_ms=500,
  on_change_async_validate=@core.async_validator(...),
)
field.set_value("x")
clock.run_all()   // 防抖窗口 + 校验完成，一次推进
```

字段组（组级校验 + 错误分发 + 组内提交）：

```moonbit
// fn step1_l() -> Lens[Form, Step] —— 访问器定义同上
let step1 = form.group(
  step1_l(),
  on_submit_validate=@core.group_validator_value(g => {
    if g.name == "" {
      @core.GroupValidationResult::group_and_fields(
        "Step incomplete",
        [(@core.Key::field("name"), "Name is required")],
      )
    } else {
      @core.GroupValidationResult::valid()
    }
  }),
)
step1.mount()
step1.handle_submit(
  on_group_submit=(value, _meta) => submit_step1(value),  // 表单提交态不受影响
  on_group_submit_invalid=() => show_group_errors(),
)
```

组校验器也可以直接用 moonschema 编译的 schema（错误按 JSON-Pointer 组内相对路径
分发给子字段，见 `/schema` 包）：

```moonbit
let step_schema = @builder.object({ "name": @builder.string().min_len(2) }).compile()...
let step1 = form.group(
  step1_l(),
  on_submit_validate=@formSchema.schema_group_validator(step_schema),
)
```

React（tiye/react）：

```moonbit
let bridge = @formreact.FieldBridge::make(form, email_l())
let handle = @formreact.use_field_handle(bridge)
let state = @react.use_sync_external_store(
  () => handle.subscribe(),
  () => handle.get_snapshot(),
)
// state.value / state.errors / state.is_touched ...
```

组状态（React）——`GroupBridge` 前缀订阅整棵子树，子字段的任何变化
（含分发到的错误）都刷新组快照：

```moonbit
let step1 = form.group(step1_l(), on_submit_validate=...)
let gbridge = @formreact.GroupBridge::make(step1)
let ghandle = @formreact.use_group_handle(gbridge)
let gstate = @react.use_sync_external_store(
  () => ghandle.subscribe(),
  () => ghandle.get_snapshot(),
)
// gstate.value / gstate.errors / gstate.is_valid / gstate.can_submit ...
gbridge.submit(on_group_submit=(v, _) => submit_step1(v))
```

表单级状态（React）——`FormBridge` 订阅整个表单，驱动提交按钮态与表单级错误：

```moonbit
let fbridge = @formreact.FormBridge::make(form)
let fhandle = @formreact.use_form_handle(fbridge)
let fstate = @react.use_sync_external_store(
  () => fhandle.subscribe(),
  () => fhandle.get_snapshot(),
)
// fstate.is_submitting / fstate.can_submit / fstate.submit_error ...
fbridge.submit(submit_options=...)
```

真实时钟（js 宿主）——测试里用虚拟时钟，宿主里桥接真实定时器（同一协议）：

```moonbit
let form = @core.FormApi::make(values).with_clock(@formreact.real_clock())
// 防抖/异步提交走真实时间；测试中换成 VirtualClock 即确定性推进
```

更多见 [examples/README](src/examples/README.md)。**浏览器 demo**（登录表单 +
FormGroup 分步表单，无头浏览器 15 项检查全过）：[web/](web/README.md)。

## 测试与验收

```bash
moon test --target js      # 308 tests（含上游译文 + 文档测试）
moon test --target wasm    # 288 tests
moon test --target native  # CI 已验证（GitHub Actions 五作业全绿）
moon run src/examples/login --target js   # 示例验收
```

三目标 `moon check` 零警告；CI 覆盖 check×3 目标 + test×3 目标 + 示例运行
（[workflow](.github/workflows/ci.yml)）。

上游对账：**185 个译文测试**覆盖 form-core@1.33.5 全部 342 个用例的行为语义
（含 FormGroup 31 / FieldGroup 20）；豁免清单（utils dot-path 机器/
mergeForm/类型层测试等）与有意偏离（值语义/虚拟时钟/lens 组合吞并
FieldGroup 等 9 项）逐条记录于
[upstream/PARITY.md](upstream/PARITY.md)。

## 致谢

- [TanStack Form](https://github.com/TanStack/form)（MIT）——行为语义基准
- [QuietlyChan/moonschema](https://github.com/QuietlyChan/moonschema)（Apache-2.0）——schema 校验引擎，源码 vendor 于 `src/vendor/moonschema`
- [tiye/react](https://mooncakes.io/docs/#/tiye/react/)——React 绑定

## License

MIT
