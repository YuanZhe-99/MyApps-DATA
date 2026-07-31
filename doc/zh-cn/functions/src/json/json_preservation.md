# lib/src/json/json_preservation.dart

泛型、模式驱动和平铺映射的 JSON 未知字段保留引擎（P2.2）。从 MyDay（模式驱动递归遍历）和 MyDevice（平铺 `extraJson` 三方合并）抽取；两种风格都导出，因此每个应用保留自己既有的保留策略。应用字段名模式不在这里——它们留在应用侧，调用时传入。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `JsonListPreservation` | 类 | A | 描述如何在对象列表的每一项中匹配并保留未知字段。 |
| `JsonPreservationSchema` | 类 | A | 描述一个 JSON 对象层级的已知形态。 |
| `JsonPreservation` | 类（静态工具） | A | 模式驱动的递归未知字段保留（MyDay 风格）。 |
| `unknownJsonFields` | 函数 | A | 从映射中提取未知键（MyDevice 风格）。 |
| `mergeUnknownJsonFields` | 函数 | A | 未知字段映射的三方合并（MyDevice 风格）。 |
| `jsonValueEquals` | 函数 | A | 规范（键排序）JSON 值相等性。 |

（另有私有辅助函数 `_canonicalJson`、`_copyMap`、`_stringKeyMap`、`_copyJsonValue`。）

## 行为

### 模式驱动引擎（`JsonPreservation`）

- `preserve({next, sources, schema})` 按顺序把每个来源中的未知键重新注入 `next`，并递归进入已知的 `objectFields`、`keyedObjectFields` 和 `listFields`（按 `JsonListPreservation.keyField` 匹配）。
- `preserveJsonString({...})` 和 `encodeForFile({...})` 是 `preserve` 的字符串/文件便捷封装；格式错误的来源会被忽略。
- 已知键总是来自 `next`；未知键来自来源。

### 平铺映射引擎（`unknownJsonFields` / `mergeUnknownJsonFields`）

- `unknownJsonFields(json, knownKeys)` 只返回不在 `knownKeys` 中的键。
- `mergeUnknownJsonFields({primary, secondary, base})` 对每个键：
  - 双方都有 + 有 base：只有 secondary 变化则取 secondary，否则取 primary；
  - 双方都有、无 base：取 primary；
  - 只有一侧有：取那一侧；
  - 两侧都没有（只有 base）：删除。
- `jsonValueEquals` 按规范（键排序）JSON 编码比较，因此映射键顺序不影响变更检测。
