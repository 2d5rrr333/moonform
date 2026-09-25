# 上游快照来源（SOURCES）

语义基准：**TanStack form-core@1.33.5**（npm dist-tag `latest` 于 2026-08-11 发布，v1 线终点）。

- Git tag：`@tanstack/form-core@1.33.5`
- 路径：`packages/form-core/tests/`（该 tag 下）
- tests 目录 tree SHA：`31a06e11fa1f7316d4eed27bdbc50d6061aace38`
- 已验证：main 分支 `packages/form-core/src` 15 文件与该 tag 逐字节一致（GitHub contents API SHA 比对，2026-09-19）——"对标 main" 由此成立；若未来 main 分叉，以本快照为准。
- 许可：本目录内的 `*.spec.ts` / `utils.ts` 文件来自 TanStack Form（MIT License，Copyright (c) 2021-present Tanner Linsley，全文见 [LICENSE-TANSTACK-FORM](LICENSE-TANSTACK-FORM)）。仅作行为等价翻译的参照快照随包分发，moonform 本体为其独立实现，未复制其源代码。
- moonform 本体许可证：MIT（见仓库根 [LICENSE](../LICENSE)）。

本目录文件（GitHub API blob SHA，供完整性校验）：

| 文件 | SHA | 用途 |
|---|---|---|
| FormApi.spec.ts | `024b319f0abdadc6106880b0fe7addb15ce661c5` | 译文覆盖（148 tests） |
| FieldApi.spec.ts | `7c9a468ab83e8c3eb186ac78c6329a88f11d723b` | 译文覆盖（106 tests） |
| standardSchemaValidator.spec.ts | `463dac1737e0f52cb1f6dcbe8007a1493eb759fa` | 改写为 Resolver 协议等价测试（18 tests） |
| DynamicValidation.spec.ts | `41b8ed401d36fb43947fd0f107530e91af84c44c` | 译文覆盖（9 tests） |
| fieldMeta.spec.ts | `e1aa5908178157d7b86693814b092aec1be899e3` | 译文覆盖（8 tests） |
| formOptions.spec.ts | `b716983dc87d36ad6ee9e7b9a3ddf3ccee28a5ff` | 译文覆盖（1 test） |
| transform.spec.ts | `f67b39352c9ec0ea25bf08122789121887289ce2` | 译文覆盖（1 test） |
| utils.spec.ts | `29d9a53a006646993c5eec6e38221cfb00579d95` | **豁免**（83 tests，dot-path 机器被 lens→key 取代） |
| FormGroupApi.spec.ts | `02d684fc1bc3c57c69d63b5cf57d00a442732313` | 译文覆盖（26/31 tests，2026-09-25；余 5 篇 onDynamic/revalidateLogic 豁免 D-P3） |
| FieldGroupApi.spec.ts | `2ff20790dad42841be96e4acfd802a055eadfa3f` | lens 组合等价译文（16/20 tests，2026-09-25；4 篇字符串重映射机器随设计吞并 D-P8） |
| mergeForm.spec.ts | `972b6772fa96af8e5f6f3cf027036e74a1e30566` | **豁免**（11 tests，SSR 场景） |
| utils.ts | `5e4d0305ec2fed0a268c54379018c1a67a8f3f90` | 测试辅助（sleep 等），仅参照 |

未下载（全部豁免）：`*.test-d.ts` 类型层测试 7 篇（TS 类型体操，被编译期安全的访问器设计取代）。

译文覆盖口径与豁免理由逐篇对账见 [PARITY.md](PARITY.md)。
