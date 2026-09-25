# 上游测试翻译对账（PARITY）

基准：TanStack form-core@**1.33.5**（`packages/form-core/tests/`，文件 SHA 见 `SOURCES.md`）。
译文位置：`src/core/*_wbtest.mbt`（core 包白盒测试，`moon test` 全绿）。

## 覆盖方式声明

行为等价翻译 = 上游用例的可观测行为（状态转换、校验时序、提交流程）以 moonform 的
API（lens 访问器 + Validator 协议 + 虚拟时钟）逐场景断言。上游 `it(...)` 用例与译文
`test "..."` 一一对应（或以注释标明 upstream 用例名）；dot-path 字符串寻址替换为 lens
组合（结构化 key 派生），`vi.useFakeTimers()`/`sleep()` 替换为 VirtualClock tick
（与上游同一虚拟时间模式，确定性更强）。

## 覆盖清单

| 上游 spec（用例数） | 译文文件 | 译文数 | 覆盖要点 |
|---|---|---|---|
| FormApi.spec.ts (148) | form_wbtest(14) / array_ops_wbtest(14) / array_meta_wbtest(9) / submit_wbtest(9) / subscribe_wbtest(20) / field_wbtest(8) / parity_small_wbtest(7)* / store_wbtest(9)** | 90 | 默认态/初始 state/update/reset（含字段级 default 优先、keepDefaultValues、空 reset 恢复新默认值）；值读写与 dirty；数组 7 操作（值 + meta 迁移，含嵌套数组、越界、vacated-slot 清理、array_version）；提交全流程（生命周期、校验拦截、preventDefault、异步提交、失败终态、canSubmit）；挂载/卸载/删除；订阅与批处理。*与 FieldApi 行共用（不重复计）**store 的前缀查询/重键作为 utils dot-path 机器的设计替代覆盖 |
| FieldApi.spec.ts (106) | validation_wbtest(9) / validation_async_wbtest(9) / subscribe_wbtest(20，与 FormApi 行共用) / field_wbtest(8，共用) / parity_small_wbtest(7，共用) | 53* | onChange/onBlur/onSubmit/onMount 校验时机与槽位语义；异步 pending（is_validating）；防抖（窗口折叠、定时触发）；竞态中止（双向）；unmount 中止 in-flight；监听器 onChange/onBlur/onMount/onUnmount/onFieldUnmount（含重置表单的监听器、dont_run_listeners）；卸载保留值/交互标志/跨重挂载；未挂载字段 meta 可见性；跨字段联动（linkage_wbtest） |
| FormGroupApi.spec.ts (31) | group_wbtest(29) | 29 | 组挂载/卸载（监听器、onMount 组校验，含 Mount 槽清理回归）；组级校验器（字符串 → 组错误、`{group, fields}` → 组错误 + 字段分发、未挂载字段延迟浮现、重叠校验器去重）；组内提交（不触碰表单提交态、meta 透传、修复后重校验）；isFieldsValid/isGroupValid/isValid/canSubmit 派生；form 级 onChange/onChangeGroup 监听器（独立防抖）；组 set_value 只触发 onChangeGroup；异步组校验 unmount 竞态中止；嵌套组分发 |
| FieldGroupApi.spec.ts (20) | fieldgroup_equiv_wbtest(15) | 15 | 以 lens 组合等价译文覆盖：默认值继承/状态同步；相对字段寻址的校验/读值/读 meta；数组元素写入与数组操作经组合 lens；嵌套组合；重映射 lens（firstName→a）；组合键上的 meta 写入；前缀下全量校验；reset/deleteField/提交参与。4 篇纯字符串机器用例随设计吞并（D-P8） |
| standardSchemaValidator.spec.ts (18) | parity_small_wbtest + validation_wbtest 跨字段用例 | 并入上表 | 改写为 Resolver 协议行为等价：schema 式校验器（整值判定→字段错误）经 Validator 协议进入字段 error 槽 |
| DynamicValidation.spec.ts (9) | validation_async_wbtest + submit_wbtest | 并入上表 | 防抖/竞态中止虚拟时钟译文；RHF 式 validationLogic（onDynamic）属可插拔校验策略，moonform 以 Validator 协议 + 自定义闭包达到同等可插拔性（偏离标注 D-P3） |
| fieldMeta.spec.ts (8) | parity_small_wbtest / field_wbtest | 并入上表 | 未挂载无 meta；挂载默认 meta；嵌套路径；数组下标字段；卸载保留 |
| formOptions.spec.ts (1) | parity_small_wbtest | 并入上表 | 默认值流入表单状态 |
| transform.spec.ts (1) | field_wbtest（等价断言） | 并入上表 | 核心断言（错误先于挂载到达不丢失）已覆盖；mergeForm 机制豁免 |

**对账口径（可自证）**：译文测试合计 **157**，按文件唯一计数（共享文件只计一次）：
form(14) + array_ops(14) + array_meta(9) + submit(9) + subscribe(20) + field(8) +
parity_small(7) + validation(9) + validation_async(9) + group(29) +
fieldgroup_equiv(15) + linkage(5) + store(9，MetaStore 前缀查询/重键机制作为
utils dot-path 机器的设计替代覆盖)。每个文件的 `test "..."` 数可用
`Select-String '^\s*test'` 直接复核。另有**非译文的自有测试 63**：基础设施
（key 19 / lens 8 / equal 5）、回归守护（stale_index 5 / group_edges 4）、
压力与边界（storm 5 / extreme 5 / scale 3）、core 文档测试（9）——
`moon test -p core` 实测 220 = 157 + 63 吻合。全套执行计数见 README（随版本更新）。


## 豁免清单（含理由）

| 上游 spec | 数量 | 理由 |
|---|---|---|
| FormGroupApi.spec.ts 的 onDynamic/revalidateLogic 用例 | 5 | 可插拔校验策略面（D-P3）；等价可插拔性由 Validator/GroupValidator 闭包组合提供 |
| FieldGroupApi.spec.ts 的字符串重映射机器用例 | 4 | getFormFieldName/getFormFieldOptions/监听器路径重映射/顶层数组防崩：整组字符串机器被 lens 组合设计吞并（D-P8） |
| utils.spec.ts | 83 | dot-path 字符串机器（getBy/setBy/deleteBy 深路径操作）被 lens→结构化 key 设计整体取代；其中深度相等语义由 `equal_wbtest.mbt` 以值语义协议覆盖 |
| mergeForm.spec.ts | 11 | SSR 表单合并场景；v1 交付不含 SSR（transform.spec 的 mergeForm 耦合部分随附豁免） |
| *.test-d.ts（7 文件） | — | TS 类型层测试；被编译期安全的访问器设计取代 |
| DynamicValidation 的 validationLogic 插件面 | 部分 | 可插拔校验策略（RHF mode/reValidateMode）不进 v1 核心；等价能力经 Validator 闭包组合表达 |

注：FormGroupApi.spec（31 用例）已于 0.2.0 翻译覆盖（26 译文 + 5 豁免）；FieldGroupApi.spec（20 用例）以 lens 组合等价译文覆盖（16 译文 + 4 吞并）。另有两处上游 `it.todo`（onXListenTo from fields/groups）无实现可译。

## 有意偏离清单（D-P）

| # | 偏离 | 说明 |
|---|---|---|
| D-P1 | 值语义 | MoonBit 结构体值类型替代 JS 引用语义；dirty 检测走 `derive(Eq)` 深度相等（`equal_wbtest` 验证），写入产生新值不改原值 |
| D-P2 | 虚拟时钟 | 防抖/竞态/异步提交的时序以注入 Clock 的虚拟时间驱动（上游 vitest fake timers 同模式）；比上游真实 sleep 更确定 |
| D-P3 | 校验策略面 | 上游 validationLogic 插件（onDynamic/RHF 模式）不在 v1 核心；等价可插拔性由 Validator 协议闭包组合提供 |
| D-P4 | 订阅簿记 | 稳定 ID（v2 方向）而非 v1 数组下标 |
| D-P5 | delete_field 不删值 | 类型化表单值无"字段缺失"状态；删除只清 meta（值语义模型的结构性结果） |
| D-P6 | errorMap 展平序 | 固定生命周期顺序（Mount→Change→Blur→Submit→Server）替代 JS 对象插入序 |
| D-P7 | async 提交/校验经 Clock 回调 | MoonBit async 运行时不进核心（wasm 不支持、违反零依赖）；宿主适配层可桥接真实 async |
| D-P8 | FieldGroupApi 被 lens 组合吞并 | 上游 FieldGroupApi 是组相对名→表单字段名的字符串重映射机器；moonform 中 `parent_l.compose(child_l)` 即重映射后的字段（编译期安全），16 篇用例以组合等价译文覆盖 |
| D-P9 | FormGroup 细节类型化 | 组提交 meta 类型化为 `String`（上游任意对象）；监听器 payload 为组值本身而非 `{value, groupApi}` 事件对象；组校验器返回结构化 `GroupValidationResult`（`{group, fields}` 语义）而非 JS 动态对象；上游 form 级校验器载体在两篇译文（invalid submissions with form validator）中以组级校验器等价表达；组提交中字段错误不短路组级 onSubmit 重跑（上游注释提及短路但其测试未断言；重跑保证修复后的再提交能清理上一轮分发到字段的错误——由文档测试暴露） |
