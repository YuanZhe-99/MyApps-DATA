# lib/src/webdav/sync_progress.dart

WebDAV 同步、强制上传和强制下载操作共享的、与 UI 无关的进度类型。P2.1 在 SHA-256 和 `git diff --no-index` 确认三个应用副本逐字节相同后，原样移动了此文件。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `SyncPhase` | 枚举 | A | 定义高层操作阶段。 |
| `SyncProgress` | 类 | A | 保存一份不可变的进度快照。 |
| `SyncProgress(...)` | 构造函数 | A | 创建带可选详情和条目计数的快照。 |
| `SyncProgress.fraction` | getter | A | 返回钳制后的可度量进度，不确定时返回 null。 |
| `SyncProgress.isRunning` | getter | A | 区分活跃阶段与空闲和终止阶段。 |
| `SyncProgressListenable` | 类型别名 | A | 暴露应用 UI 消费的只读可监听类型。 |

## 行为

### `SyncPhase`

顺序是特征化契约的一部分：

`idle`、`connecting`、`downloadingData`、`merging`、`uploadingData`、`uploadingImages`、`downloadingImages`、`done`、`error`。

服务只报告阶段和原始的文件/图像详情。每个应用仍负责把阶段映射为本地化的用户可见文本。

### `SyncProgress`

- **输入：** 必填的 `phase`、可选的原始 `detail`，以及可选的 `current`/`total` 计数。
- **返回：** 适合 `ValueNotifier` 的不可变快照。
- **副作用：** 无。
- **备注：** 计数默认为零。`total` 为零表示该阶段不确定。

`SyncProgress.idle` 是标准的静止快照。

### `fraction`

- **返回：** `current / total` 钳制到 `0.0..1.0`，当 `total <= 0` 时返回 null。
- **用法：** 直接绑定到 `LinearProgressIndicator.value`。

### `isRunning`

- **返回：** 对 `idle`、`done` 和 `error` 返回 false；对其它每个阶段返回 true。
- **备注：** `done` 和 `error` 是终止快照，不是活跃操作。

### `SyncProgressListenable`

`ValueListenable<SyncProgress>` 的别名。使用者在监听时无法获得对服务底层 `ValueNotifier` 的修改权限。
