# lib/src/merge/sync_merge.dart

泛型三方记录合并引擎（P2.3）。统一 MyAnime/MyDay/MyDevice 的 `mergeRecords<T>` 变体：MyAnime 和 MyDay 逐字节相同；MyDevice 是严格超集，多一个可选 `mergeUnknownFields` 回调（此处采纳）。应用特有的合并包装器和 `mergeAssignments` 留在应用侧。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `RecordConflict<T>` | 类 | A | 一条记录级冲突（ID 相同、两侧都变化）。 |
| `RecordMergeResult<T>` | 类 | A | 合并后的列表加上未解决的冲突。 |
| `mergeRecords<T>` | 函数 | A | 使用 `modifiedAt` 按 ID 三方合并记录。 |

## 行为（由 P0.1 矩阵 §E 钉定）

对每个 ID，用 `base` 检测哪一侧变化：

| 场景 | 结果 | 冲突？ |
|---|---|---|
| 只有本地变化 | 本地 | 否 |
| 只有远程变化 | 远程 | 否 |
| 两侧都变化、序列化内容相同 | 本地 | 否 |
| 两侧都变化、内容不同 | 冲突（若 `autoResolve` 则 LWW） | 是（除非自动解决） |
| 两侧都没变化 | 本地 | 否 |
| 只有一侧新增 | 纳入 | 否 |
| 一侧删除、另一侧未变 | 排除（删除传播） | 否 |
| 一侧删除、另一侧已修改 | 保留修改 | 否 |
| 两侧都删除 | 排除 | 否 |
| 无 base、两侧新增相同 ID | 按 `modifiedAt` LWW（平局取远程） | 否 |

- `autoResolve` 默认为 `false`（PLAN 不变量 I4）。
- `serialize`（可选）启用相同内容冲突抑制。
- `mergeUnknownFields`（可选，MyDevice 模式）让带模型级 `extraJson` 的应用在合并中保留未知字段；没有它时，主记录原样返回（MyAnime/MyDay 模式）。
