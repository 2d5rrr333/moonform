# moonform 项目状态速查

> 用途：新会话打开时把本文件发给 AI，即可无缝接续。最后更新：2026-09-19。

## 项目是什么

**moonform** — MoonBit 原生 headless 表单状态库，语义对标 TanStack form-core@1.33.5（SHA 已验证 = main 分支）。
- 仓库：https://github.com/2d5rrr333/moonform（master，18 commits）
- mooncakes：`2d5rrr333/moonform@0.1.1`（0.1.0/0.1.1 均在线，latest=0.1.1）
- OpenSpec：变更 `add-moonform-core` 已归档，主 specs 在 `openspec/specs/moonform/`（7 capability）
- 位置：`D:\code\moonbit\moonform`（workspace 根 `D:\code\moonbit`，其 openspec/ 记录了对账）

## 包结构

| 包 | 说明 |
|---|---|
| src/core | 零依赖：FormApi/FieldApi 状态机、Key/Lens（(key,get,set,try_get) 三+一元组）、MetaStore、订阅（稳定ID+批处理）、虚拟 Clock、Validator 协议（同步+异步防抖/竞态中止）、数组7操作+meta迁移、提交编排 |
| src/rules | 零依赖：required/min-max length/int/value/pattern/contains/starts_with/email/url/equals/must_be_true/non_blank/numeric/custom |
| src/schema | moonschema 适配（QuietlyChan/moonschema@0.1.0 源码 vendor 在 src/vendor/moonschema，Apache-2.0，因未上 mooncakes） |
| src/react | FieldBridge（attach_with_notify 契约）+ use_field（js 目标） |
| src/lens-gen | .mbti 解析器 + lens 生成器（幂等、改名安全） |
| src/examples | login（moonschema 校验）+ roster（数组 meta 迁移演示） |
| src/web-demo | 浏览器登录组件（tiye/react） |
| web/ | 浏览器 demo 宿主页 + self-test.html + headless 验证工具 |
| upstream/ | form-core@1.33.5 测试源 + PARITY.md（143 译文对账）+ SOURCES.md + MIT 许可文本 |

## 验证命令（全部应绿）

```bash
cd moonform
moon test --target js       # 217
moon test --target wasm     # 212
moon check --target js/wasm/native   # 0 警告
moon run src/examples/login --target js
moon run src/examples/roster --target js
node tools/headless-verify.cjs        # 浏览器 5/5（需先构建拷贝 web/main.js）
```

## 关键技术事实（避免重新踩坑）

- MoonBit 无自定义 derive；`.mbti`（moon info 产物）是 lens-gen 的输入
- `*_test.mbt` 是黑盒（跨包），`*_wbtest.mbt` 是白盒；黑盒下别包 enum 构造器只读
- MoonBit 无 `await`；async 依赖 moonbitlang/async（wasm 不支持）→ 核心用虚拟 Clock 注入
- tiye/react 受控 input 必须 `on_change`（on_input 会 abort）；vdom 传 JS 前必须 `to_js_obscure()`
- React 19 无 UMD → web/ vendor 了 React 18.3.1 UMD + `ReactDOMClient` 别名 shim
- `moon.mod` 是 TOML 风格（fmt 转换过）；包清单 `moon.pkg`
- 本机网络：github.com HTTPS 偶发不可达（git push 需重试）；`moon update` 的 git 索引克隆坏（用 API 手动补过索引）

## 未完事项

1. **申报书（大赛）**：需用户人工撰写（章程要求），素材在 `moonform/PROPOSAL-NOTES.md`；截止 **2026-09-24 24:00**（飞书问卷）
2. 可选后续：FormGroup/FieldGroup、moonschema 上游正式发布后解除 vendor、lens-gen CLI 化、0.1.x 迭代

## 大赛章程要点（OSC 2026 / 9月黑客松）

- 申报需 GitHub 仓库 ≥10 有效 commits（现 18 ✓，禁止拆分造假）
- 验收：CI（check/build/test）✓、README 可复现 ✓、mooncakes 发布 ✓、OSI 许可+移植声明 ✓（README 致谢 + upstream/ MIT 文本）
- 自查 skill：`osc2026-guide`（review mode 可跑完整检查）
