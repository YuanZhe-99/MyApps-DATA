# 行为契约：硬不变量

这些是本共享包绝不能破坏的规则。它们是当初抽取的验收标准，如今在三个已发布应用依赖本包的情况下仍是兼容性契约——在这里违反规则可能使已在线的安装陷入困境。

最初这是已退役的一次性抽取计划中的"硬不变量"表。它放在这里是因为它是行为契约，而不是项目管理历史。

| # | 不变量 |
|---|---|
| I1 | 远程 WebDAV 布局不变：相同的数据文件名、`images/` 子目录、`.lock` 文件名和 JSON 模式。**旧应用构建和新构建必须能在同一服务器上同步互通。** |
| I2 | 本地格式不变：`webdav_config.json`、`.sync_base/*`（含 `upload_lock.json`）、`backups/backup_*.json`（写入 v2、可恢复 v1）、`backups/blobs/`、`storage_config.json` 键。 |
| I3 | 锁语义：60 秒 TTL、20 秒心跳、过期锁接管规则、锁写入不重试。重试：最多 2 次额外尝试、1 秒/2 秒退避、仅瞬态 + 5xx、绝不 4xx。 |
| I4 | 冲突绝不静默自动解决（每个调用点的 `autoResolve: false`，手动与自动同步一致）。 |
| I5 | 恢复在首次写入前禁用 `webdav_config.json` 中的自动同步；仅当 `wroteAnything == false` 时重新启用。 |
| I6 | UTC 时间戳；美化打印 JSON（`withIndent('  ')`）；未知 JSON 字段在解析→合并→写入往返中存活。 |
| I7 | 每个应用既有的公共服务 API（`WebDAVService`、`BackupService`、`ImportExportService`、`AutoSyncService`——静态类，含 `@visibleForTesting appDirProvider`）通过门面保留，使**所有既有应用测试无需修改全部通过**。 |
| I8 | 面向用户的字符串（浮出到 UI 的警告、错误）逐字节相同，除非下方某项已接受统一另有说明。 |
| I9 | 所有新/移动代码都带函数解释层文档注释块；每个应用的 AGENTS.md 在同一变更集中更新。 |
| I10 | 真实 Gitea 地址绝不出现在任何已提交文件中。 |

## 统一规则

当三个应用在某项无关紧要的差异上有两个已经一致时，**采取好的统一**——让那个不同的应用改为一致，而不是为了保留漂移而增加按应用开关。开关是共享引擎中的永久复杂度；无关紧要的漂移不值得背负。只有统一会真正破坏功能时才保留差异。

真正的按应用需求保持可配置：MyDay 的 `ReminderService` 驱动备份、它的整文件汇率合并、MyDevice 的合成 `images` 模块和 `mergeAssignments`。

禁止的是*静默*选择，而不是深思熟虑的选择。每项已接受统一必须向所有者标记、记录在下方并附上其行为后果，并反映在重新录制的 golden 中。

## 已接受的统一

| 变更 | 后果 |
|---|---|
| **N2c** — 逐文件上传错误字符串 | MyAnime 采用了 MyDay/MyDevice 的 `'$name: force-upload failed: …'`。一个用户可见字符串发生了改变，这就是 I8 带例外条款的原因。 |
| **G3** — 下载错误处理 | MyAnime 从中止整个同步改为逐文件错误收集（引擎默认 `failFastOnDownloadError: false`）。单模块下可观察结果不变。 |
| **Finalize 重新下载** | MyAnime 的 `finalizePendingSync` 现在在上传前先发一次 `GET <data file>`，与 MyDay/MyDevice 一致。每次 finalize 多花一次请求，并增加"远程不可读则中止"的守卫——严格更安全，因为它防止把解决结果上传到一个刚刚变得不可读的远程上。MyAnime 的 `sync_conflict_finalize` golden 已重新录制；差异恰好是插入的那一次 GET。 |
| **ZIP 路径穿越拒绝** | 含路径穿越条目的归档现在被整体拒绝（导入返回 false、什么都不写），而不是跳过坏条目、导入其余部分。MyAnime 和 MyDevice 采用了 MyDay 的行为。两种方式下都不会有东西落到应用目录之外；变化在于被篡改的归档不再可能被半套用。 |
| **恢复防抖取消** | 恢复在同步前取消挂起的保存防抖，而不是让它留在队列中。MyDevice 采用了 MyAnime 的行为；进行中守卫已使差异不可观察。 |

## 逐行为细节的位置

仓库根目录的 [feature-matrix.md](feature-matrix.md) 是对应用原始实现的三方审计——每个行为点、每个应用怎么做的、它是变成 `fixed` 还是 `config` 开关。修改同步、备份或 ZIP 引擎的任何东西之前先读它。
