# lib/src/storage/storage_adapter.dart

所有共享引擎的应用提供存储边界。本包绝不直接导入 AnimeStorage、TodoStorage 或 DeviceStorage。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `StorageAdapter` | 抽象类 | A | 暴露活动的应用目录和应用存储配置持久化。 |
| `getAppDir` | 抽象方法 | A | 解析活动的自定义/默认应用数据目录。 |
| `readConfig` | 抽象方法 | A | 通过应用存储中枢读取 `storage_config.json`。 |
| `writeConfig` | 抽象方法 | A | 持久化 `storage_config.json`，同时保留应用自有的键。 |

## 契约

`getAppDir()` 是 `WebDavSyncEngine` 使用的唯一路径来源；数据文件、`images/`、`webdav_config.json` 和 `.sync_base/` 都在该目录之下解析。每个应用适配器必须委托给它既有的存储中枢，使自定义路径保留当前行为。

`readConfig()` 和 `writeConfig()` 指的是 `storage_config.json`，不是 `webdav_config.json`。P2.6 显式地在应用目录下持久化 WebDAV 配置。配置方法属于共享适配器的一部分，供后续备份/存储引擎使用。
