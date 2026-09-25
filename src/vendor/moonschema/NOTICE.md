# vendored moonschema — 来源与本地修改披露

- 上游：https://github.com/QuietlyChan/moonschema @ 0.1.0（Apache-2.0，全文见本目录 [LICENSE](LICENSE)）
- 引入原因：上游未发布到 mooncakes.io，`2d5rrr333/moonform/schema` 适配层需要其源码
- 引入范围：`schema/`、`rules/`、`builder/` 三个包的全部 `.mbt` 源码与其测试

## 本地修改（相对上游 0.1.0）

1. **工具链迁移补丁（2026-09-25）**：随 MoonBit 工具链 0.1.20260920 的
   `implicit_impl_as_method` 弃用策略，为全部 `derive(...)`/显式 `impl` 类型追加
   `pub extend T with Trait::{...}` 声明（`schema/types.mbt`、`rules/expr.mbt`、
   `rules/lexer.mbt`）。纯机械迁移，不改变任何行为语义；上游升级工具链后可对齐回上游。
2. 包清单 `moon.pkg` 按本仓库模块路径（`2d5rrr333/moonform/vendor/...`）调整。

除此以外未做任何修改；上游发布到 mooncakes 后本 vendor 将整体移除（见根 README 致谢）。
