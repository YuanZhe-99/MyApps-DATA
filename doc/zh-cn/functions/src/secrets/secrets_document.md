# lib/src/secrets/secrets_document.dart

本地 API Key 密钥文件的值类型、按键合并和规范编码器。格式与 MyTranscribe 现有写入 `transcribe_secrets.json` 的格式相同，因此现有文件读入后再编码按字节一致。密钥文件从不是数据模块。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `secretsDocumentVersion` | 常量 | A | 写入文件的格式版本（`1`）。 |
| `SecretEntry` | 类 | A | 一个密钥（或墓碑）、其 UTC `updatedAt` 和保留的未知字段。 |
| `SecretEntry(...)` | 构造器 | A | 创建条目，并把时间规范为 UTC。 |
| `SecretEntry.hasKey` | getter | A | 墓碑或空白密钥时为 false。 |
| `SecretEntry.fromJson` | 工厂 | A | 解析条目；损坏的时间戳变为纪元时间。 |
| `SecretEntry.toJson` | 方法 | A | 序列化条目；墓碑写为显式 `null`。 |
| `SecretsDocument` | 类 | A | 按记录 id 组织的条目，以及保留的顶层未知字段。 |
| `SecretsDocument(...)` | 构造器 | A | 创建不可变文档。 |
| `SecretsDocument.fromJson` | 工厂 | A | 解析文档；类型错误的 `keys` 或条目视为不存在。 |
| `SecretsDocument.toJson` | 方法 | A | 按排序后的 id 序列化。 |
| `SecretsDocument.keyFor` | 方法 | A | 某个 id 的可用密钥，或 null。 |
| `SecretsDocument.withKey` | 方法 | A | 设置（去除首尾空白）或清除（墓碑）某个 id 的密钥。 |
| `SecretsDocument.configuredIds` | getter | A | 持有可用密钥的 id；从不返回密钥值。 |
| `mergeSecretsDocuments` | 函数 | A | 带墓碑的按键后写优先合并。 |
| `encodeSecretsDocument` | 函数 | A | 本地写入和上传共用的缩进 JSON。 |

共十五个声明。

## 文件格式

```json
{
  "version": 1,
  "keys": {
    "provider:old": {
      "apiKey": null,
      "updatedAt": "2026-09-06T00:00:00.000Z"
    },
    "provider:openai": {
      "apiKey": "sk-...",
      "updatedAt": "2026-09-05T10:00:00.000Z"
    }
  }
}
```

写入时 id 排序，因此内容相同时编码字节总是相同。顶层未知字段写在 `version` 之前，条目未知字段写在 `apiKey` 之前；没有未知字段时输出与 MyTranscribe 完全相同。

## 合并规则

- 按键比较，`updatedAt` 较晚的条目获胜；时间相同时取远端副本，使各设备收敛。
- 墓碑（`apiKey: null`）参与合并，因此清除的密钥在各处都保持清除。
- 没有基线快照：每个键都是一个独立值。
- 顶层未知字段取并集，本地优先。
