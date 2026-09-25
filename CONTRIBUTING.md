# 贡献指南（Contributing）

感谢关注 moonform——MoonBit 原生 headless 表单状态库。

## 环境准备

```bash
git clone https://github.com/2d5rrr333/moonform.git
cd moonform
moon update          # 解析依赖（首次必跑；本机索引偶发滞后时重跑）
moon test --target js --deny-warn    # 应 322 全绿
```

需要 MoonBit 工具链（[安装](https://www.moonbitlang.com/download/)）。
CI 用最新工具链并逐作业记录版本（见 Actions step summary）；
本地版本较旧时以 CI 为准。

## 开发循环

```bash
moon fmt                       # 提交前必须格式化
moon check --target js --deny-warn    # 三目标零警告
moon check --target wasm --deny-warn
moon check --target native --deny-warn
moon test --target js --deny-warn     # js/wasm 双目标测试
moon test --target wasm --deny-warn
```

改动 core 后建议跑全量：

```bash
moon run src/examples/login --target js      # 示例验收
moon run src/examples/wizard --target js
node tools/headless-verify.cjs               # 浏览器 15 项（需先构建 web/main.js、web/wizard.js，见 web/README.md）
```

## 项目约定

- **行为语义**对标 TanStack form-core@1.33.5：修复/新增行为前先查
  [upstream/PARITY.md](upstream/PARITY.md) 的译文对账与偏离清单（D-P1~D-P9）；
  语义偏离必须有理由并记录在案
- **测试先行**：历史上 7 个真实 bug 全部由测试暴露；新行为请附可失败
  的回归测试（core 的测试在 `src/core/*_wbtest.mbt`，白盒）
- **文档即测试**：core/rules/schema/react 各有 `README.mbt.md` doc 测试；
  主 README 的快速开始示例由 `src/readme-verify` 对发布包持续验证——
  改 README 示例必须同步改验证器
- **生成物不手改**：`*.mbti` 由 `moon info` 再生、
  `profile_lenses.generated.mbt` 由 lens-gen CLI 再生（CI 均有漂移守卫）
- **提交信息**：conventional commits（feat/fix/perf/docs/ci/chore/test）
- **行尾**：仓库统一 LF（`.gitattributes` 已钉）；Windows 下批量改文件
  注意别写入 BOM

## 发布流程（维护者）

```bash
# 1. 版本号：moon.mod 的 version
# 2. CHANGELOG.md 增补条目
# 3. 全绿后先发布再推送（CI 的 README 验证器依赖 registry 已有该版本）：
moon publish
git tag vX.Y.Z && git push origin master --tags
```

## 许可

贡献即同意以 MIT 许可发布（见 [LICENSE](LICENSE)）。
