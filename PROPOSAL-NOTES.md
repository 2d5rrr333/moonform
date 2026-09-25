# moonform 项目说明素材

> 本文件是项目的事实素材库，汇总可验证的项目事实，按"价值定位 / 交付范围 /
> 实现路径"三个维度组织。数据截至 0.8.4。

## 项目概况

| 项 | 内容 |
|---|---|
| 项目名称 | moonform — MoonBit 原生 headless 表单状态库 |
| GitHub 仓库 | https://github.com/2d5rrr333/moonform（master） |
| 发布 | mooncakes.io `2d5rrr333/moonform@0.8.4`（0.1.0 → 0.8.4 共 14 版） |
| 参考项目 | TanStack Form（@tanstack/form-core）https://github.com/TanStack/form — MIT。**语义移植而非代码移植**：以 form-core@1.33.5（v1 终点版，已验证与 main 逐字节一致）的上游测试集为行为规格，MoonBit 原生实现 |
| 方向/通用性 | Web 基础设施：表单状态管理是所有 Web 应用的高频需求 |

## 维度 1：项目价值与生态定位（痛点 / 缺口 / 优势）

- **痛点**：表单是 Web 应用中状态最复杂的一块——字段状态机、校验编排（防抖/竞态）、
  数组字段操作、字段组、提交生命周期。每个 MoonBit Web 项目都在手写这套易错的胶水代码
- **缺口**：mooncakes.io 已有渲染层（tiye/react、kagura/moui）和校验层
  （moonschema 等数个），但**零个表单状态库**——中间的状态编排层完全空缺。
  下游"React 绑定 + 校验器"都已就位，唯独没有东西把它们串起来
- **优势**（对比生态外方案）：
  - 对比 tiye/react 手写 useState 表单：完整的 dirty/touched/错误派生/提交编排，
    不是每个组件重复造轮子
  - 对比"将来用 TanStack Form 的 JS 版"：纯 MoonBit、类型安全、三目标
    （js/wasm/native）同构——同一校验定义前端后端复用，无 JS FFI 边界
  - 行为正确性不靠自夸：上游 342 个测试用例的**行为等价翻译**做验收规格
    （157 个译文 + 豁免/偏离对账，见 upstream/PARITY.md）

## 维度 2：交付范围与工程边界

**已交付**（v0.4.0，已发布 mooncakes.io）：
- core：FormApi/FieldApi 状态机、结构化访问器（lens，替代 dot-path 字符串）、
  数组字段 7 种操作 + meta 迁移、订阅/批处理/前缀订阅、校验协议（同步 + 异步防抖/竞态中止）、
  虚拟时钟、提交编排（preventDefault/异步提交/canSubmit）、
  FormGroupApi（组级校验 + 错误分发到子字段 + 组内提交）、
  form 级 onChange/onChangeGroup 监听器（独立防抖）、FieldApi::reset
- rules：零依赖内置规则包（required/min/max/length/pattern/email/url/one_of 等 18 个规则）
- schema：moonschema 适配——字段级（schema_field_validator）与**组级**
  （schema_group_validator，JSON-Pointer 错误按组内相对路径分发）
- react：tiye/react 适配器——FieldBridge/use_field + GroupBridge/use_group
  （前缀订阅整棵子树）+ FormBridge/use_form（整表快照）+ real_clock 宿主时钟
  （真实定时器桥接，与测试中的 VirtualClock 同一协议）
- lens-gen：.mbti 驱动的访问器生成器 + CLI（生成物可编译、CI 再生成防漂移）
- examples：login（schema 校验）+ roster（数组 meta 迁移）+ wizard（分步组表单）+ generated（lens-gen 产物端到端）+ isomorphic（js 客户端 + native 服务端）
- web/：浏览器 demo——登录表单 + 分步组表单 + 异步提交（无头浏览器 15 项检查全过）

**明确不做**（工程边界）：
- mergeForm/SSR 场景、devtools、多框架适配（v1 只交付 tiye/react）
- 不逐行翻译 TS 代码——只对标行为语义，实现服从 MoonBit 语言特性
  （值语义、结构化 key 替代字符串路径）

## 维度 3：实现路径与技术理解

三条关键路径决策（探索阶段 spike 验证过，非拍脑袋）：
1. **dot-path 字符串 → 结构化 lens**：TS 用字符串路径 + 类型体操；MoonBit 没有这套
   机制，改为 `(key, get, set)` 三元组组合子——编译期安全、重构改名不失配，
   key 由组合派生支撑数组 meta 迁移、字段组前缀查询与前缀订阅（上游三大测试块）
2. **Promise/微任务 → 虚拟时钟协议**：MoonBit 的 async 运行时不支持 wasm 且违反
   核心零依赖约束；防抖/竞态/异步提交全部对注入的 Clock 协议实现——测试确定性
   虚拟时间推进（上游 vitest fake timers 本就是同模式）
3. **行为等价翻译做验收**：不逐行翻译，把上游测试集翻译成 MoonBit 测试
   （157 篇译文），豁免与偏离逐条记录在案（PARITY.md）——可审计、可复现

## 三个完整使用场景

1. **React 登录/注册表单**：tiye/react + moonschema 实时校验 email/password，
   错误按字段呈现，提交拦截（示例已含：`moon run src/examples/login --target js`；
   浏览器版见 web/index.html）
2. **同构校验复用**（examples/isomorphic，可运行产物）：一份字段校验器定义，
   js 客户端做逐字段实时反馈，native 服务端用同一份定义做最终把关
   （绕过 UI 的恶意载荷全字段拒绝）——CI 双目标跑，零序列化损耗、零逻辑重复
3. **多步向导表单**（FormGroup 全栈）：schema 作组校验器，错误分发到子字段；
   组提交逐步把关、互不干扰；最终经真实时钟异步整表提交，提交中状态可见
   （`moon run src/examples/wizard --target js`；
   浏览器版 web/wizard.html，无头 10 项检查全过）

## 工程数据（佐证"真实可用"）

- 自有 MoonBit 代码 ~10,400 行 .mbt（其中测试 ~4,750 行；另有 vendored moonschema
  ~3,600 行已隔离披露，本地补丁逐条记录于 vendor NOTICE.md）
- 测试 322（js）/ 298（wasm）全绿；native CI 通过；三目标 `moon check --deny-warn`
  0 警告；`moon fmt --check` 通过；接口文件随 CI 漂移守卫同步
- CI（GitHub Actions）五作业全绿：check×3 目标（含 fmt + 接口漂移守卫）、
  test×3 目标、示例运行
- 浏览器 demo：无头 Edge 15 项检查全过（登录 5：渲染/错误呈现/清除/提交；
  向导 10：schema 分发/组拦截/步骤流转/双通道校验/异步提交中态/完成）
- 已发布：mooncakes.io `2d5rrr333/moonform@0.8.4`
- 开源合规：MIT；上游 TanStack Form MIT（upstream/ 附许可文本与 SHA 溯源）；
  vendored moonschema Apache-2.0（保留其 LICENSE + 本地修改披露）；差异对照表 PARITY.md
- 过程质量：真实 bug 修复 7 例均由测试暴露（数组过期索引崩溃、React notify 契约、
  组提交后 stale 分发错误、组 onMount 错误永不清除、数组操作×组分发的迁移时序、
  组清理无中生有 meta 条目）
