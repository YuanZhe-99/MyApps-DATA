# lib/src/backup/backup_engine.dart

泛型本地备份引擎（P2.7），从三个应用的 `backup_service.dart` 实现（feature-matrix §J）调和而成。备份格式 v2 捆绑存储逐模块的原始 JSON 字符串，外加一个 `_imageRefs` 映射，指向内容寻址的 `backups/blobs/<sha256><ext>` 存储，带引用计数 GC；带内联 base64 `_images` 的旧 v1 捆绑仍可恢复。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `BackupClock` | 类型别名 | A | 提供当前本地时间；可为测试注入。 |
| `RestoreResult` | 类 | A | 报告恢复成功、写入标志和缺失图像数。 |
| `RestoreResult` | 构造函数 | A | 创建一个不可变的恢复结果。 |
| `BackupInfo` | 类 | A | 描述一个被列出的备份捆绑。 |
| `BackupInfo` | 构造函数 | A | 创建一个不可变的备份信息条目。 |
| `BackupInfo.displaySize` | getter | A | 以与应用相同的方式格式化 B/KB/MB。 |
| `BackupEngine` | 类 | A | 创建/列出/恢复/删除备份，外加每日自动备份。 |
| `BackupEngine` | 构造函数 | A | 绑定存储、注册表和 J 开关。 |
| `BackupEngine.loadSettings` | 方法 | A | 从配置读取 `autoBackupEnabled`/`backupRetentionDays`。 |
| `BackupEngine.saveSettings` | 方法 | A | 持久化这两个键，保留无关的配置键。 |
| `BackupEngine._getBackupDir` | 私有方法 | A | 解析/创建 `backups/`。 |
| `BackupEngine._getBlobDir` | 私有方法 | A | 解析/创建 `backups/blobs/`。 |
| `BackupEngine._formatStamp` | 私有静态方法 | A | 不用 `intl` 格式化 `yyyyMMdd_HHmmss`。 |
| `BackupEngine._parseStamp` | 私有静态方法 | A | 严格解析文件名时间戳。 |
| `BackupEngine.createBackup` | 方法 | A | 原子地写入 v2 捆绑，然后做保留 + blob GC。 |
| `BackupEngine.runAutoBackupIfNeeded` | 方法 | A | 受守卫的每日一次自动备份。 |
| `BackupEngine.listBackups` | 方法 | A | 最新优先列出，带损坏标志和 blob 大小。 |
| `BackupEngine.getBackupModules` | 方法 | A | 报告一个捆绑中的模块 id。 |
| `BackupEngine._safeImageBasename` | 私有静态方法 | A | 宽容的平铺图像键净化（J17）。 |
| `BackupEngine._loadWebDavConfig` | 私有方法 | A | 为 I5 交互加载 `webdav_config.json`。 |
| `BackupEngine._saveWebDavConfig` | 私有方法 | A | 原子地持久化 `webdav_config.json`。 |
| `BackupEngine._enableAutoSyncAfterUntouchedRestore` | 私有方法 | A | 尽力而为地重新启用自动同步。 |
| `BackupEngine.restoreBackup` | 方法 | A | 先校验后写入的恢复，带 I5 自动同步开关。 |
| `BackupEngine.deleteBackup` | 方法 | A | 删除捆绑，然后垃圾回收 blob。 |
| `BackupEngine._cleanOldBackups` | 私有方法 | A | 按龄保留（0 = 永久）。 |
| `BackupEngine._collectUnreferencedBlobs` | 私有方法 | A | 保守的引用计数 blob GC。 |

## 捆绑格式（固定，I2/C8）

`createBackup` 写入 `backups/backup_<yyyyMMdd_HHmmss>.json`，恰好包含 `{'_backupFormat': 2}`、每个既存模块文件一个键（注册表顺序，值为该文件原始 JSON 文本字符串），以及只在存在图像时的 `_imageRefs`（`'images/<name>' -> '<sha256><ext>'`）。没有 `createdAt`，也没有 `modules` 字段（更正 C8）。`_images` 是只读的旧 v1 格式。

## Blob 存储与 GC

图像按 sha256 内容寻址存储在 `backups/blobs/` 下；任意数量的备份间的相同字节共享同一个物理 blob（已存在时跳过写入）。GC 在每次创建和删除后运行，对每个剩余捆绑做引用计数，遇到任何不可解析的捆绑时中止整趟（J10），并且绝不删除比 `blobGcGrace`（默认 10 分钟，J9）更年轻的 blob，因此并发的 `createBackup` 绝不会被竞态。

## 恢复

`restoreBackup` 在首次写入前通过 `DataModule.validate` 校验每个被选模块的负载（K8），用 P2.4 辅助原子写入，并从 v2 blob 引用或旧 v1 内联 base64 恢复图像。缺失 blob 增加 `missingImages` 但不使恢复失败。图像键用 MyDevice 的宽容 `_safeImageBasename`（J17）净化：接受裸基名和 `images/<name>` 键；拒绝路径穿越、嵌套和绝对路径。

启用 `syntheticImagesModule`（J3；仅 MyDevice）时，`getBackupModules` 在一个捆绑携带任一种图像格式的情况下追加 `images` 模块 id，并且图像恢复以该模块被选中为前提。否则图像总是恢复。

## I5 自动同步交互

当 `webdav_config.json` 存在、已配置且 `autoSync: true` 时，`restoreBackup` 在首次文件写入**之前**禁用自动同步。如果随后恢复以 `wroteAnything == false` 失败（本地数据可证明未被触碰），则尽力而为地重新启用自动同步；在其它所有结果下它保持关闭。恢复后的强制上传提议仍是应用侧 UI。

## 自动备份

`runAutoBackupIfNeeded` 有可重入守卫、每次调用重新加载设置，并且每个日历日最多创建一个备份。"今天已备份"检查扫描捆绑文件名并忽略损坏捆绑，因此被中断的写入会被重试（J14/J15）。不持久化 `lastBackupAt` 键（L3）。触发节奏由宿主拥有（J21/H5）：MyAnime/MyDevice 从它们的自动同步计时器调用它；MyDay 从它的 `ReminderService` 30 秒循环调用它。
