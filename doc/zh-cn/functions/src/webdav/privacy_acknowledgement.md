# lib/src/webdav/privacy_acknowledgement.dart

WebDAV 隐私提醒的按设备确认记录。应用拥有提醒版本（数据范围或条款发生实质变化时提升的整数），并根据本文件计算的状态决定何时暂停或恢复同步。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `webDavPrivacyAcknowledgementKey` | 常量 | A | 默认 `storage_config.json` 键，`webdavPrivacyAcknowledgement`。 |
| `WebDavPrivacyAcknowledgement` | 类 | A | 已确认的提醒版本、UTC 时间和保留的未知字段。 |
| `WebDavPrivacyAcknowledgement(...)` | 构造器 | A | 创建记录，并把时间规范为 UTC。 |
| `WebDavPrivacyAcknowledgement.tryParse` | 静态方法 | A | 解析已存储的值；格式错误的值视为不存在。 |
| `WebDavPrivacyAcknowledgement.toJson` | 方法 | A | 连同未知字段序列化记录。 |
| `WebDavPrivacyStatus` | 枚举 | A | `acknowledged`、`firstEnable`、`syncPaused`。 |
| `needsAcknowledgement` | 函数 | A | 未存储记录或存储版本较旧时为 true。 |
| `webDavPrivacyStatus` | 函数 | A | 为同步门控和界面判断设备状态。 |
| `WebDavPrivacyAcknowledgementStore` | 类 | A | 通过注入回调实现的设备本地持久化。 |
| `WebDavPrivacyAcknowledgementStore(...)` | 构造器 | A | 绑定读写回调。 |
| `WebDavPrivacyAcknowledgementStore.storageConfig` | 工厂 | A | 通过 `StorageAdapter` 把记录存到 `storage_config.json` 的一个键下。 |
| `load` | 方法 | A | 读取已存储的记录。 |
| `acknowledge` | 方法 | A | 记录对某个版本的确认。 |
| `clear` | 方法 | A | 删除记录。 |

共十四个声明。

## 存储的记录

```json
{
  "noticeVersion": 1,
  "acknowledgedAt": "2026-10-06T12:00:00.000Z"
}
```

## 行为

- `needsAcknowledgement(stored, currentVersion)` 在 `null` 或版本低于 `currentVersion` 时为 true。存储版本较新（例如降级后）视为已确认。
- 同步已配置但未确认时，`webDavPrivacyStatus` 返回 `syncPaused`，这覆盖升级后的现有用户。应用保留配置和待同步数据，显示 `MyAppsWebDavSyncPausedBanner`，在用户确认前不运行同步。
- `firstEnable` 表示必须在第一个网络请求之前显示提醒；拒绝时不存储任何内容。
- 该记录从不是数据模块：不同步、不备份、不导出，因此每台新设备都会显示提醒。
- `storageConfig` 工厂执行读-改-写并保留其他所有键；已有记录的未知字段在 `acknowledge` 后仍然保留。
- 这里的任何内容都不改变 WebDAV 线格式、远端布局、`.lock` 语义或冲突处理。
