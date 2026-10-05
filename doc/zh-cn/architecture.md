# 架构

## 本包是什么

`myapps_data` 是共享的 Flutter 包，承载 WebDAV 同步引擎和数据管理引擎（备份/恢复、ZIP 导入/导出，以及它们共享的底层设施）。应用通过模块描述符、存储适配器和领域回调接入。

本包集中维护可由应用通过门面提供的公共服务逻辑：

```
lib/shared/services/webdav_service.dart
lib/shared/services/sync_merge.dart
lib/shared/services/sync_progress.dart
lib/shared/services/sync_wake_lock.dart
lib/shared/services/auto_sync_service.dart
lib/shared/services/backup_service.dart
lib/shared/services/import_export_service.dart
```

本包集中维护这些逻辑。每个应用保留自己的数据模型、UI、存储中枢和应用特有的合并包装器。具体接入方式和验证记录在应用自身文档中。

## 行为契约

在这里做任何结构性工作之前，先阅读 [invariants.md](invariants.md)。它包含：

- 本包必须维护的**硬不变量**（I1–I10）——WebDAV 线上格式、锁语义（60 秒 TTL、20 秒心跳）、恢复备份时在首次写入前禁用自动同步的规则、让每个应用测试都通过的门面规则，以及真实 Gitea 主机永不提交到任何地方的规则。
- **统一规则**和已接受统一的清单，每一项都附带其行为后果。

共享行为和可配置策略见 [feature-matrix.md](feature-matrix.md)。

## 包结构

通用数据管理设置呈现位于 `lib/src/settings/`。操作行和备份偏好接受应用文案、
状态和回调；共享包管理呈现，应用保留路由和存储。

`lib/src/` 按区域组织：`storage/`（`StorageAdapter`、原子 I/O）、`json/`（JSON 保留引擎）、`merge/`（`mergeRecords<T>`）、`modules/`（`DataModule`/`ModuleRegistry`）、`webdav/`（配置、客户端、上传锁、同步引擎、进度）、`sync/`（自动同步调度器、唤醒锁）、`backup/`（备份引擎）、`data/`（ZIP 传输）。公共 API 只通过 `lib/myapps_data.dart` 导出；使用者不得直接导入 `src/` 路径。

## 当前状态（完整并在生产中）

以下每个引擎区域都已实现并经过单元测试。进度和唤醒锁工具包括：

- `lib/src/webdav/sync_progress.dart`：共享的进度阶段、不可变的进度快照，以及应用 UI 消费的 `ValueListenable` 类型别名。
- `lib/src/sync/sync_wake_lock.dart`：引用计数、所有权安全的前台同步唤醒锁。它从不禁用另一个功能拥有的锁，并把插件失败视为尽力而为。

其余引擎区域提供：

- `lib/src/json/json_preservation.dart`：模式驱动和平铺映射的未知字段保留。
- `lib/src/merge/sync_merge.dart`：泛型三方 `mergeRecords<T>` 引擎。
- `lib/src/storage/atomic_io.dart`：同目录 tmp-重命名式的字符串/字节写入，以及可选的失败可恢复串行写入队列。
- `lib/src/webdav/webdav_config.dart`：共享的 `WebDAVConfig`（服务器 URL、凭据、远程路径、自动同步标志、`.nextcloud()` 工厂、JSON 往返）。
- `lib/src/webdav/upload_lock.dart`：`WebDAVUploadLock`（远程 `.lock` 值类型，带 TTL/过期/匹配/刷新）和 `UploadSession`（会话句柄）。
- `lib/src/webdav/webdav_client.dart`：纯 `WebDavClient` 传输——PROPFIND/MKCOL/GET/PUT/DELETE 动词、HTTP Basic 认证、URL 规范化、I3 重试策略（2 次额外尝试、1s/2s 退避、仅 5xx）、远程上传锁原语（带 `If-Match`/`If-None-Match` 和 `retries: 0` 的读/写/删除）、锁心跳机制，以及判别式 `RemoteFile`/`RemoteFileStatus` 下载结果。所有 TTL/心跳/超时/退避开关都可注入，并带有固定默认值。
- `lib/src/storage/storage_adapter.dart`：应用提供的活动存储根/配置边界。
- `lib/src/modules/data_module.dart`：有序的 `ModuleRegistry`、应用自有的合并/校验/保留/图像回调、不透明的待定状态，以及逐模块冲突解决构建器。
- `lib/src/webdav/sync_engine.dart`：`WebDavSyncEngine` 的配置/基线/客户端 ID 持久化、完整的远程/本地上传锁生命周期、原始缺失/相等快速路径、模块合并和一次性本地重读、待定/最终化流程、粘性本地变更信号、仅引用添加式图像同步、进度、强制上传和强制下载。它按操作接受 WebDAV 配置，因此应用门面可以在配置页值未保存的情况下保留手动同步。
- `lib/src/backup/backup_engine.dart`：`BackupEngine` v2 捆绑创建（逐模块原始 JSON 字符串 + `_imageRefs`，无 `createdAt`/`modules`）、sha256 内容寻址 blob 存储并带引用计数 GC（10 分钟宽限、遇不可解析中止）、按龄保留、受守卫的每日自动备份、损坏捆绑标记、带 I5 自动同步禁用交互的写前校验 v1/v2 恢复、合成 `images` 模块开关，以及宽容的图像键净化器（J17）。
- `lib/src/data/zip_transfer.dart`：`ZipTransfer` 注册表驱动 ZIP 导出（模块文件 + `images/<basename>`、按应用的归档名前缀）和两阶段校验导入，采用严格路径穿越拒绝，带可配置的宽容开关（`rejectUnknownEntries`、`strictUtf8`、`validateBeforeWrite`、`atomicWrites`）和可选的导入后钩子。
- `lib/src/sync/auto_sync_scheduler.dart`：`AutoSyncScheduler` 生命周期观察、防抖（30 秒）、周期（15 分钟）自动同步核心，带 `_syncing` 守卫、内存状态、重载/状态监听器，以及应用钩子（`isAutoSyncActive`、`runSync`、`consumeLocalDataChanged`、`onPeriodicTick`、`onResume`），它们保留每个应用的触发拓扑和副作用。

所有 API 都从 `lib/myapps_data.dart` 导出，并由聚焦的单元测试覆盖。36 个包自有的 golden 固定件对含 1、5 和 4 个模块的合成注册表运行十个特征同步场景以及备份 v2 和 ZIP 导出格式检查；未过滤的 CI 测试命令负责验证它们。当前声明清单见 [functions/INDEX.md](functions/INDEX.md)。

### 应用边界

应用可通过薄门面保留公共服务 API。领域合并策略、合并后迁移、上传前保留、
备份触发和图像选择由应用负责，通过明确的钩子接入。

## 应用如何接入本包

每个应用把本仓库作为 git **子模块**嵌入到 `packages/myapps_data`，使用相对 URL `../MyApps-DATA.git`（因此它按应用自身被克隆自的主机——Gitea 或 GitHub——解析），外加一个 pub **路径依赖**：

```yaml
dependencies:
  myapps_data:
    path: packages/myapps_data
```

由于 pub 不锁定路径依赖的内容，子模块提交 SHA 就是实际生效的锁文件。应用在任何应用发布前固定到一个**打了标签**的发布提交；这里的变更必须先推送到两个远程（`origin` 和 `github`），才能提升任何应用的子模块指针。

## 约定

- **函数解释层**：每个函数、方法、构造函数、getter 和 setter 的正上方都带一个结构化的 `/// Purpose: / Inputs: / Returns: / Side effects: / Notes:` 文档注释。本文档集把这个注释当作第一手事实来源，对注释未完全覆盖的内容再读实现。
- 任何跨设备比较的内容都使用 **UTC 时间戳**。
- 通过 `JsonEncoder.withIndent('  ')` 输出**美化打印的 JSON**。
- **未知 JSON 字段**在解析 → 合并 → 写入的全过程中被保留。
- 本包内**不包含任何应用特有知识**：没有应用模型导入、没有硬编码的逐应用数据文件清单、没有本地化的面向用户字符串。应用特有行为通过 `DataModule` 描述符和 `StorageAdapter` 接口注入。
- 许可证：GPL-3.0。

## 文档维护

引擎代码落入 `lib/src/` 后，每个新区域必须在同一变更集中获得一个 `doc/en-us/functions/` 页面（一旦 `doc/zh-cn/` 存在，还要有对应的中文翻译）——确切规则见本仓库的 `AGENTS.md`。
