# moonform 项目状态速查

> 用途：新会话打开时把本文件发给编程助手，即可无缝接续。最后更新：2026-09-25（0.3.0）。

## 项目是什么

**moonform** — MoonBit 原生 headless 表单状态库，语义对标 TanStack form-core@1.33.5（SHA 已验证 = main 分支）。
- 仓库：https://github.com/2d5rrr333/moonform（master）
- mooncakes：`2d5rrr333/moonform`（0.1.0/0.1.1/0.2.0 在线；**0.3.0 待发布**——本地已 bump 版本，需 `moon publish`）
- OpenSpec：变更 `add-moonform-core` 已归档，主 specs 在 `openspec/specs/moonform/`（7 capability）
- 位置：`D:\code\moonbit\moonform`（workspace 根 `D:\code\moonbit`，其 openspec/ 记录了对账）

## 包结构

| 包 | 说明 |
|---|---|
| src/core | 零依赖：FormApi/FieldApi 状态机、Key/Lens、MetaStore、订阅（稳定ID+批处理+**前缀订阅 subscribe_under**）、虚拟 Clock、Validator 协议、数组7操作+meta迁移、提交编排、FormGroupApi（组级校验/错误分发/组内提交）、form 级 onChange/onChangeGroup 监听器、FieldApi::reset |
| src/rules | 零依赖：required/min-max length/int/value/pattern/contains/starts_with/email/url/equals/must_be_true/non_blank/numeric/custom |
| src/schema | moonschema 适配（QuietlyChan/moonschema@0.1.0 源码 vendor 在 src/vendor/moonschema，Apache-2.0，因未上 mooncakes） |
| src/react | FieldBridge + use_field、**GroupBridge + use_group（前缀订阅整棵子树）**（js 目标） |
| src/lens-gen | .mbti 解析器 + lens 生成器（幂等、改名安全） |
| src/examples | login（moonschema 校验）+ roster（数组 meta 迁移）+ **wizard（FormGroup 分步表单）** |
| src/web-demo | 浏览器登录组件（tiye/react） |
| web/ | 浏览器 demo 宿主页 + self-test.html + headless 验证工具 |
| upstream/ | form-core@1.33.5 测试源 + PARITY.md（185 译文对账）+ SOURCES.md + MIT 许可文本 |

## 验证命令（全部应绿）

```bash
cd moonform
moon test --target js --deny-warn       # 269
moon test --target wasm --deny-warn     # 258
moon check --target js/wasm/native --deny-warn   # 0 警告
moon fmt --check
moon info                                # 接口文件同步（pkg.generated.mbti）
moon run src/examples/login --target js
moon run src/examples/roster --target js
moon run src/examples/wizard --target js
node tools/headless-verify.cjs        # 浏览器 5/5（需先构建拷贝 web/main.js）
# native test 需 C 编译器（moonschema vendor），本地没有 → CI 的 ubuntu 上跑
```

## 0.3.0 内容（2026-09-25，FormGroup 全栈贯通）

- react：GroupBridge + use_group/use_group_handle（GroupState 快照：value/errors/is_valid 三态/can_submit/组内 attempts；submit 便捷转发）
- core：`FormApi::subscribe_under(prefix, kinds?)` 前缀订阅（组/子树适配器的天然原语；Sub 增加 prefix 字段）
- examples/wizard：双通道组校验（组级错误 + 字段分发并存）、组提交互不干扰、整表提交门槛；进 CI
- CI 加固：check/test 全部 --deny-warn、moon fmt --check、moon info 接口漂移守卫（*.mbti git diff --exit-code）
- 0.2.0 的 FormGroupApi 译文与 PARITY 记账见上一节（185 译文）

## 关键技术事实（避免重新踩坑）

- MoonBit 无自定义 derive；`.mbti`（moon info 产物）是 lens-gen 的输入
- `*_test.mbt` 是黑盒（跨包），`*_wbtest.mbt` 是白盒；黑盒下别包 enum 构造器只读
- **可选参数（`label? : T`）调用时直接传值，不要包 `Some(...)`；函数体内拿到的是 `T?`，向另一个可选参数转发需 unwrap 或分支**（GroupBridge::submit 用 unwrap_or 合成默认回调）
- **wbtest 内不能声明局部 struct**；匿名 record 字面量按字段名结构化解析——新增带 `v`/`n` 等通用字段名的 struct 会与既有 cell 冲突（跨文件！User/Count/StrCell 等），用唯一字段名或显式类型标注
- 单字段 struct 的 setter 用 `{ field: v }` 整体构造，spread `..s` 报 unused_struct_update 警告（deny-warn 会挂）
- MoonBit 无 `await`；async 依赖 moonbitlang/async（wasm 不支持）→ 核心用虚拟 Clock 注入
- tiye/react 受控 input 必须 `on_change`（on_input 会 abort）；vdom 传 JS 前必须 `to_js_obscure()`
- React 19 无 UMD → web/ vendor 了 React 18.3.1 UMD + `ReactDOMClient` 别名 shim
- `moon.mod` 是 TOML 风格（fmt 转换过）；包清单 `moon.pkg`
- 本机网络：github.com HTTPS 偶发不可达（git push 需重试）；`moon update` 的 git 索引克隆坏（走 127.0.0.1 代理时不可达；publish 的 HTTPS 通道正常）
- 本机无 C 编译器 → native test 只能在 CI 跑（native check 可以）

## 未完事项

1. **0.3.0 发布**：`moon publish`（版本已 bump，CHANGELOG/README 已就绪）
2. 申报书：需用户人工撰写，素材在 PROPOSAL-NOTES.md（已刷新至 0.2.0 口径；提交前把 0.3.0 的 GroupBridge/wizard/CI 加固补进去）
3. 可选后续：moonschema 上游正式发布后解除 vendor、lens-gen CLI 化、mergeForm/SSR、浏览器 demo 增加 wizard 页
4. 章程要求：仓库文件中不得出现特定自动化工具类字样（已全库清理；web/vendor 与构建产物中的第三方压缩/生成标识符除外）

## 大赛章程要点（OSC 2026 / 9月黑客松）

- 申报需 GitHub 仓库 ≥10 有效 commits（禁止拆分造假）
- 验收：CI（check/build/test）✓、README 可复现 ✓、mooncakes 发布 ✓、OSI 许可+移植声明 ✓（README 致谢 + upstream/ MIT 文本）
- 自查 skill：`osc2026-guide`（review mode 可跑完整检查）
