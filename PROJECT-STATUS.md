# moonform 项目状态速查

> 用途：新会话打开时把本文件发给编程助手，即可无缝接续。最后更新：2026-09-25（0.8.1）。

## 项目是什么

**moonform** — MoonBit 原生 headless 表单状态库，语义对标 TanStack form-core@1.33.5（SHA 已验证 = main 分支）。
- 仓库：https://github.com/2d5rrr333/moonform（master）
- mooncakes：`2d5rrr333/moonform`（0.1.x–0.7.1 全部在线，latest=0.8.1）
- OpenSpec：变更 `add-moonform-core` 已归档，主 specs 在 `openspec/specs/moonform/`（7 capability）
- 位置：`D:\code\moonbit\moonform`（workspace 根 `D:\code\moonbit`，其 openspec/ 记录了对账）

## 本地工具链（重要）

**已升级到 moon 0.1.20260920 / moonc 0.10.14**（2026-09-25，与 CI latest 一致）。
历史版本不可从 cli.moonbitlang.com 下载（只有 latest/nightly），所以**不要降级**。
新工具链的两个迁移要求已全库完成：
1. `implicit_impl_as_method`：所有 derive/显式 impl 需要 `pub extend T with Trait::{...}`（已加 136 处，含 vendor 补丁——披露在 src/vendor/moonschema/NOTICE.md）
2. `test_unqualified_package`：黑盒测试引用本包项需限定（@rules./@react./@schema.）；连字符包名（lens-gen）自引用别名不可用 → 其测试已转白盒（lens_gen_wbtest.mbt）
另：README.mbt.md 的 doc 测试块标记若被破坏会**静默**不编译不计数（` ```mbt check ` 三反引号），改动后务必核对测试总数（js 306）。

## 包结构

| 包 | 说明 |
|---|---|
| src/core | 零依赖：FormApi/FieldApi 状态机、Key/Lens、MetaStore、订阅（稳定ID+批处理+前缀订阅 subscribe_under）、虚拟 Clock、Validator 协议、数组7操作+meta迁移、提交编排、FormGroupApi（组级校验/错误分发/组内提交）、form 级 onChange/onChangeGroup 监听器、FieldApi::reset、GroupValidationResult::make、Clock::make |
| src/rules | 零依赖：required/min-max length/int/value/pattern/contains/starts_with/email/url/equals/**one_of**/must_be_true/non_blank/numeric/custom + doc 测试 |
| src/schema | moonschema 适配：字段级 schema_field_validator + **组级 schema_group_validator**（JSON-Pointer 错误按组内相对路径分发；vendor 源码在 src/vendor/moonschema，Apache-2.0 + NOTICE.md） |
| src/react | FieldBridge/use_field、GroupBridge/use_group（前缀订阅）、FormBridge/use_form（整表快照）、real_clock 宿主时钟（js 目标） |
| src/lens-gen | .mbti 解析器 + lens 生成器（幂等、改名安全）；测试为白盒 |
| src/lens-gen-cli | 生成器 CLI（js）：`moon run src/lens-gen-cli -- <pkg.mbti> [-o <out.mbt>] [core_alias]` |
| src/examples | login（schema 校验）+ roster（数组 meta 迁移）+ wizard（FormGroup 分步表单）+ generated（CLI 生成访问器的端到端证明，CI 再生成守卫）+ isomorphic（js 客户端 + native 服务端，CI 双目标） |
| src/web-demo | 浏览器登录组件（tiye/react）→ web/main.js |
| src/web-demo-wizard | 浏览器分步组件（schema 组校验 + 双通道）→ web/wizard.js |
| web/ | 浏览器 demo 宿主页（index/wizard + 两份 self-test）+ headless 验证（14 项） |
| upstream/ | form-core@1.33.5 测试源 + PARITY.md（185 译文对账）+ SOURCES.md + MIT 许可文本 |

## 验证命令（全部应绿）

```bash
cd moonform
moon test --target js --deny-warn       # 306
moon test --target wasm --deny-warn     # 286
moon check --target js/wasm/native --deny-warn   # 0 警告
moon fmt --check
moon info                                # 接口文件同步（pkg.generated.mbti）
moon run src/examples/login --target js
moon run src/examples/roster --target js
moon run src/examples/wizard --target js
moon run src/examples/isomorphic-client --target js
moon run src/examples/isomorphic-server --target native  # 需 C 编译器 → CI 跑
moon run src/examples/bench --target js           # 500 字段性能基准（计时输出）
# 浏览器 14 项（需先构建拷贝 web/main.js 与 web/wizard.js）：
moon build src/web-demo --target js --release; Copy-Item _build\js\release\build\web-demo\web-demo.js web\main.js
moon build src/web-demo-wizard --target js --release; Copy-Item _build\js\release\build\web-demo-wizard\web-demo-wizard.js web\wizard.js
node tools/headless-verify.cjs          # login 5 + wizard 10（含异步提交中间态）
# native test 需 C 编译器（moonschema vendor），本地没有 → CI 的 ubuntu 上跑
```

## 版本轨迹（本仓库会话内）

- 0.2.0：FormGroupApi + form 级监听器 + FieldApi::reset；译文 143→185
- 0.3.0：GroupBridge/use_group（react）+ core 前缀订阅 + wizard 示例 + CI 加固（deny-warn/fmt/接口漂移守卫）
- 0.3.1：工具链迁移（0.1.20260920：136 处 pub extend、测试限定、vendor 补丁+NOTICE、web/main.js 重建）
- 0.4.0：schema_group_validator（schema 包）+ GroupValidationResult::make + 浏览器 wizard demo（web/wizard.html，无头 14 项）+ **修复组 onMount 错误永不清除**（字段语义对齐）
- 0.5.0：FormBridge/use_form（react 整表桥接）+ real_clock 宿主时钟（core Clock::make 入口）+ 嵌套组分发测试 + wizard demo 异步提交（无头 15 项）
- 0.6.0：lens-gen CLI + examples/generated（生成物可编译证明 + CI 再生成守卫）+ schema 包 doc 测试
- 0.7.0：examples/isomorphic（场景 2 落地：共享校验定义，js 客户端 + native 服务端，CI 双目标跑）+ SOURCES.md 修悬空引用
- 0.7.1：热路径优化（has_prefix 零分配、has_errors 早退、派生状态首中即返/单遍扫描）+ examples/bench（500 字段计时基准，CI 跑）+ 规模冒烟测试
- 0.8.0：rules one_of/one_of_str + rules/react doc 测试（四个用户面包全部带可执行文档）
- 0.8.1：**修复 bug×2**（数组操作先写值后迁移 meta，打乱组分发错误 → 改为先迁移；组清理对缺失 key 无中生有建 meta 条目 → 跳过缺失 key）+ 组×结构变更边界测试（update/delete_field/数组×组）

## 关键技术事实（避免重新踩坑）

- MoonBit 无自定义 derive；`.mbti`（moon info 产物）是 lens-gen 的输入
- `*_test.mbt` 是黑盒（跨包），`*_wbtest.mbt` 是白盒；黑盒下别包 enum 构造器只读；**黑盒测试引用本包项必须 @pkg. 限定**；连字符包名无自引用别名
- **可选参数（`label? : T`）调用时直接传值；函数体内是 `T?`，转发需 unwrap/分支**（GroupBridge::submit 用 unwrap_or 合成默认）
- **wbtest 内不能声明局部 struct**；匿名 record 字面量按字段名跨文件结构化解析（User/Count/StrCell 等冲突），用唯一字段名或显式类型标注
- 单字段 struct 的 setter 用 `{ field: v }` 整体构造；spread `..s` 报 unused_struct_update（deny-warn 会挂）
- 新工具链：derive 类型需配对 `pub extend`（私有测试类型也用 pub）；extends 会进入 .mbti 公开面
- StringBuilder 用 `write_char`/`write_string`（无 push_char）；String 切片 `s[a:b].to_owned()`（substring/to_string 均已弃用）
- tiye/react：`@react.div([...])` 位置参数即 children（不要 `div([], [...])`）；button 有 `on_click`；受控 input 必须 `on_change`（on_input 会 abort）；vdom 传 JS 前必须 `to_js_obscure()`
- MoonBit 无 `await`；async 依赖 moonbitlang/async（wasm 不支持）→ 核心用虚拟 Clock 注入
- React 19 无 UMD → web/ vendor 了 React 18.3.1 UMD + `ReactDOMClient` 别名 shim
- PowerShell 5.1 `Set-Content -Encoding UTF8` 会加 BOM——批量改文件用 `[System.IO.File]::WriteAllText` + `UTF8Encoding($false)`
- 本机网络：github.com HTTPS 偶发不可达（git push 需重试）；`moon update` 的 git 索引克隆走 127.0.0.1 代理常不可达（publish 的 HTTPS 通道正常）
- 本机无 C 编译器 → native test 只能在 CI 跑（native check 可以）

## 未完事项

1. **0.8.1 发布**：moon publish（版本已 bump，CHANGELOG/README 已就绪）
2. 申报书：需用户人工撰写，素材在 PROPOSAL-NOTES.md（已刷新至 0.8.1 口径）
3. 可选后续：moonschema 上游正式发布后解除 vendor、lens-gen CLI 化、mergeForm/SSR（lens-gen CLI 已完成）
4. 章程要求：仓库文件中不得出现特定自动化工具类字样（已全库清理；web/vendor 与构建产物中的第三方压缩/生成标识符除外）

## 大赛章程要点（OSC 2026 / 9月黑客松）

- 申报需 GitHub 仓库 ≥10 有效 commits（禁止拆分造假）
- 验收：CI（check/build/test）✓、README 可复现 ✓、mooncakes 发布 ✓、OSI 许可+移植声明 ✓（README 致谢 + upstream/ MIT 文本 + vendor NOTICE.md）
- 自查 skill：`osc2026-guide`（review mode 可跑完整检查）
