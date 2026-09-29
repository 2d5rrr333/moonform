# vendored moonschema — 来源与本地修改披露

- 上游：https://github.com/QuietlyChan/moonschema @ 0.1.0（Apache-2.0，全文见本目录 [LICENSE](LICENSE)）
- 引入原因：上游未发布到 mooncakes.io，`2d5rrr333/moonform/schema` 适配层需要其源码
- 引入范围：`schema/`、`rules/`、`builder/` 三个包的全部 `.mbt` 源码与其测试

## 本地修改（相对上游 0.1.0）

1. **工具链迁移补丁（2026-09-25）**：随 MoonBit 工具链 0.1.20260920 的
   `implicit_impl_as_method` 弃用策略，为全部 `derive(...)`/显式 `impl` 类型追加
   `pub extend T with Trait::{...}` 声明（`schema/types.mbt`、`rules/expr.mbt`、
   `rules/lexer.mbt`）。纯机械迁移，不改变任何行为语义；上游升级工具链后可对齐回上游。
2. **format 断言崩溃修复（2026-09-29，moonform）**：`schema/format.mbt` 的
   `is_email`/`is_uuid` 混用 `String::length()`（UTF-16 单元数）与
   `to_array()`（码点数组）——含增补平面字符（emoji）的输入越界 abort。
   统一按码点遍历。行为差异仅在原本崩溃的输入上。
3. **递归守卫与指针/词法修复（2026-09-29，moonform）**：
   - `schema/validate.mbt` + `schema/compile.mbt` + `schema/types.mbt`：
     `$ref` 循环（如 `{"$ref": "#"}`）与超深嵌套模式此前无界自递归导致
     栈溢出 abort——新增 `Ctx::depth`，编译与校验均于 256 层截断
     （编译报 `InvalidSchema`，校验记录一条错误）。
   - `schema/pointer.mbt`：`percent_decode` 此前把 `%XX` 逐字节按 Latin-1
     转码点（`#/properties/%E4%B8%AD` 解析不到中文键）——现收集字节后
     整体按 UTF-8 解码，非法序列整体原样保留。
   - `schema/compile.mbt`：`compile_count` 上界从 9e15 收紧到 Int 范围
     （原 `to_int` 静默饱和到 2147483647）；`enum` 错误消息与行为对齐
     （空数组被接受）。
   - `rules/lexer.mbt`：数字/标识符字面量此前用码点下标做 UTF-16 切片，
     前置增补平面字符使提取错位——改从码点数组拼接。
4. 包清单 `moon.pkg` 按本仓库模块路径（`2d5rrr333/moonform/vendor/...`）调整。

除此以外未做任何修改；上游发布到 mooncakes 后本 vendor 将整体移除（见根 README 致谢）。
