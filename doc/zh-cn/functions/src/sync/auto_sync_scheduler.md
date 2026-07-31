# lib/src/sync/auto_sync_scheduler.dart

泛型自动同步调度器核心（P2.9），从三个应用的 `auto_sync_service.dart` 单例（feature-matrix §H）抽取。调度器只拥有触发拓扑、`_syncing` 守卫、内存状态，以及重载/状态监听器的扇出；实际同步通过应用提供的 `runSync` 钩子运行（通常委托给 `WebDavSyncEngine.sync`）。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `AutoSyncResult` | 类 | A | 报告一次同步尝试的结果，供状态记录。 |
| `AutoSyncResult` | 构造函数 | A | 创建一个不可变的结果。 |
| `AutoSyncPredicate` | 类型别名 | A | 返回自动同步是否已配置并启用。 |
| `AutoSyncRunSync` | 类型别名 | A | 执行一次同步尝试并报告其结果。 |
| `AutoSyncConsumeLocalDataChanged` | 类型别名 | A | 消费引擎的本地数据变更标志。 |
| `AutoSyncSideEffect` | 类型别名 | A | 运行一个应用特有的周期/恢复副作用。 |
| `AutoSyncScheduler` | 类 | A | 生命周期观察、防抖、周期的自动同步核心。 |
| `AutoSyncScheduler` | 构造函数 | A | 绑定钩子和固定时长。 |
| `AutoSyncScheduler.lastSuccessAt` | getter | A | 最近一次成功同步的时间。 |
| `AutoSyncScheduler.lastFailureAt` | getter | A | 最近一次失败同步的时间。 |
| `AutoSyncScheduler.lastError` | getter | A | 最近一次同步错误消息。 |
| `AutoSyncScheduler.hasPendingConflicts` | getter | A | 是否有冲突等待手动解决。 |
| `AutoSyncScheduler.addOnLocalDataChanged` | 方法 | A | 注册一个 UI 重载回调。 |
| `AutoSyncScheduler.removeOnLocalDataChanged` | 方法 | A | 注销一个 UI 重载回调。 |
| `AutoSyncScheduler.addOnStatusChanged` | 方法 | A | 注册一个状态变更回调。 |
| `AutoSyncScheduler.removeOnStatusChanged` | 方法 | A | 注销一个状态变更回调。 |
| `AutoSyncScheduler.recordSyncResult` | 方法 | A | 记录一次手动同步结果。 |
| `AutoSyncScheduler.recordFinalizeResult` | 方法 | A | 记录一次冲突最终化结果。 |
| `AutoSyncScheduler.notifyLocalDataChangedIfNeeded` | 方法 | A | 标志被设置时触发重载监听器。 |
| `AutoSyncScheduler.notifyLocalDataChangedNow` | 方法 | A | 无条件触发重载监听器。 |
| `AutoSyncScheduler.start` | 方法 | A | 观察生命周期、启动计时器、运行首次同步。 |
| `AutoSyncScheduler.stop` | 方法 | A | 取消计时器并移除观察者。 |
| `AutoSyncScheduler.notifySaved` | 方法 | A | 安排一次 30 秒后沿防抖同步。 |
| `AutoSyncScheduler.requestSyncNow` | 方法 | A | 立即同步，取消任何挂起的防抖。 |
| `AutoSyncScheduler.didChangeAppLifecycleState` | 方法 | A | 恢复触发外加应用恢复副作用。 |
| `AutoSyncScheduler._requestSyncNow` | 私有方法 | A | 取消防抖并启动一次受守卫的同步。 |
| `AutoSyncScheduler._trySync` | 私有方法 | A | 运行一次受守卫的同步尝试并记录状态。 |
| `AutoSyncScheduler._invokeSideEffect` | 私有方法 | A | 运行可选的副作用钩子，吞掉错误。 |
| `AutoSyncScheduler._recordSuccess` | 私有方法 | A | 记录一次成功同步。 |
| `AutoSyncScheduler._recordFailure` | 私有方法 | A | 记录一次失败同步或待定冲突。 |
| `AutoSyncScheduler._fireLocalDataChanged` | 私有方法 | A | 调用所有重载监听器。 |
| `AutoSyncScheduler._notifyStatusChanged` | 私有方法 | A | 调用所有状态监听器。 |

## 触发（H1–H3）

固定的触发集被保留：应用启动（`start`）、应用恢复（仅 `resumed`）、15 分钟周期计时器、`notifySaved` 后的 30 秒后沿防抖，以及启用/保存自动同步配置后的 `requestSyncNow`。`notifySaved` 在 `start` 之前被忽略，因此早期存储写入不可能安排同步。启动、周期和恢复统一为先取消挂起的保存防抖再立即同步（MyAnime 的行为）；`notifySaved` 是唯一的后沿防抖触发。

## 守卫与状态

`_trySync` 在 `_syncing` 已为 true 时静默跳过（重叠触发被忽略，不浮出为错误）。配置门（`isAutoSyncActive`）在守卫被获取之前运行，因此未配置的尝试绝不会阻塞后续真正的同步。结果只记录在内存中（`lastSuccessAt`/`lastFailureAt`/`lastError`/`hasPendingConflicts`）并扇出给状态监听器；自动同步总是让冲突自动解决保持关闭（H4），把真正的双向冲突记录为可见的待定状态，而不是 LWW。

## 应用钩子（H5/H6）

应用特有的差异以钩子而非配置存活：`onPeriodicTick`（MyAnime/MyDevice 在这里运行每日 `BackupService.runAutoBackupIfNeeded`；MyDay 把它留空，因为它的 `ReminderService` 30 秒循环拥有备份——H5）和 `onResume`（MyAnime：备份 + 提醒；MyDay：移动提醒刷新；MyDevice：仅备份——H6）。`consumeLocalDataChanged` 接到 `WebDavSyncEngine.consumeLocalDataChanged` 上，使 `_trySync` 和 `notifyLocalDataChangedIfNeeded` 恰好在引擎写入本地数据或下载图像时重载打开的页面。
