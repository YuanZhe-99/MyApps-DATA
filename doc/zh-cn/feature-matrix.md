# 功能矩阵——共享服务三方漂移审计

> **用途：** 本页是提取审计的历史逐行为参考，审计于
> 2026-07-23 完成。它记录了 **提取前** 实现中
> **MyAnime**、**MyDay** 和 **MyDevice** 在该审计基线上的行为，以及每项
> 差异最终是协调为 **`fixed`**（一个共享实现）还是 **`config`**
> （一个命名的按应用开关）。它解释了共享包行为的来源，但不是
> 当前应用侧门面的行为说明。
>
> **范围：** 在三个应用之间进行差异比较的九个共享服务文件：
> `webdav_service.dart`, `sync_merge.dart`, `sync_progress.dart`, `sync_wake_lock.dart`,
> `auto_sync_service.dart`, `backup_service.dart`, `import_export_service.dart`,
> `json_preservation.dart`（MyDay + MyDevice；MyAnime 将保留逻辑内置于模型），
> `data_file_safety.dart`（仅 MyDay）。已于 2026-07-23 针对以下工作树完成验证：
> `C:\Users\yuanzhe\source\repos\{MyAnime,MyDay,MyDevice}` 通过 `git diff --no-index`，
> SHA-256 哈希和完整文件读取。
>
> **行号引用**采用 `file:line`（例如 `webdav_service.dart:583`），指向
> 各应用的提取前快照。除非给出完整路径，否则它们相对于各应用的
> `lib/shared/services/`（保留文件则为 `lib/shared/utils/`）
> 目录。当前应用文件已经是兼容门面，因此引用的行号
> 可能已无法定位或已包含不同代码；当前行为应查阅共享包源码、测试以及
> `doc/zh-cn/` 页面。
>
> **如何阅读一行：** `Verdict` 为 `fixed`（一个共享实现，无开关）或
> `config`（按应用开关，后面给出开关名称）。如果某行在审计基线上为 `fixed`，但
> 应用之间存在*可修正*的差异，则会写出协调目标。
> （详细协调目标见下文。）

---

## 0. “报告为相同”文件的字节一致性（P2.1 输入）

| 文件 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|
| `sync_progress.dart` | 62 行 | 62 行 | 62 行 | **fixed** — SHA-256 在三个应用中相同（已验证 `git diff --no-index` 退出码为 0）。原样移入 `lib/src/webdav/sync_progress.dart`。 |
| `sync_wake_lock.dart` | 60 行 | 60 行 | 60 行 | **fixed** — SHA-256 在三个应用中相同（已验证）。原样移入 `lib/src/sync/sync_wake_lock.dart`。 |

`sync_progress.dart` 提供 `enum SyncPhase { idle, connecting, downloadingData, merging, uploadingData, uploadingImages, downloadingImages, done, error }`、不可变的 `SyncProgress` 类（`phase`、`detail`、`current`、`total`、`fraction`、`isRunning`）以及 `typedef SyncProgressListenable = ValueListenable<SyncProgress>`。`sync_wake_lock.dart` 采用带所有权跟踪的引用计数；`acquire()`/`release()` 会吞掉所有插件错误。**没有漂移，因此无需升级到 P0.1**（PLAN P2.1 的“如果不同则升级”条件未触发）。

---

> **注意：** 本文档是提取前完成的历史三方审计。
> 其中的“PLAN”指已退役的一次性提取计划；它形成的行为契约
> 现在位于 [`invariants.md`](invariants.md)。下方逐行为发现仍是
> 历史依据；当前包行为由契约和当前
> 实现文档规定。

## 当前有效性验证（2026-08-01）

这次审计仍是提取包的有效历史依据。在迁移本页之前，
已针对当前仓库完成以下检查：

| 检查项 | 结果 |
|---|---|
| 审计基线之后的实现变更 | 未发现 2026-07-23 之后的共享包或应用引擎实现提交；后续变更仅涉及文档、子模块指针或镜像。 |
| 当前应用源码布局 | 三个应用的服务文件现在是基于 `myapps_data` 的兼容门面；因此上述旧 `file:line` 引用指向提取前历史。 |
| 当前共享包行为 | 该包仍暴露矩阵中的命名开关和已提取区域；`test/sync_merge_test.dart` 覆盖 E4 删除矩阵，WebDAV、备份、ZIP 和 golden 测试覆盖相应兼容行为。 |
| 当前契约 | 有效的兼容规则记录在 [`invariants.md`](invariants.md)；本页说明它们形成过程中的应用到包决策。 |

这项验证不会把历史应用行为重新解释为当前应用源码；它确认
提取后的实现及其测试仍体现下面记录的决策。

## 1. 提取前计划的修正

一次性提取计划的调查部分（PLAN §1）和 P0.1 条目包含若干
本审计发现**被低估或错误**的主张。记录这些内容是为了避免引擎
建立在错误前提上；这些修正已在提取共享包时应用。

| # | PLAN 主张 | 审计发现 | 影响 |
|---|---|---|---|
| C1 | "MyDevice treats 207 *and* 404 as 可达 - do the others?" (P0.1) | **三个应用均** 使用 the 相同 条件 `streamed.statusCode == 207 || streamed.statusCode == 404` (MyAnime `webdav_service.dart:583`, MyDay `:764`, MyDevice `:608`). | Not a MyDevice 差异点 -> `fixed`, 否 开关. |
| C2 | "MyDay 具有 本地 `.sync_base/upload_lock.json` - confirm MyAnime/MyDevice equivalents" (P0.1) | **三个应用均** 具有 `_localLockFileName = 'upload_lock.json'` 写入 to `.sync_base/` (MyAnime `:293`, MyDay `:330`, MyDevice `:314`) with 相同 读取/save/clear helpers. | Not MyDay-仅 -> `fixed`. |
| C3 | "probe-size cap (MyDevice `_probeMaxBytes` 4 MB - others?)" (P0.1) | **三个应用均** 定义 `static const _probeMaxBytes = 4 * 1024 * 1024;` (MyAnime `:28`, MyDay `:28`, MyDevice `:31`). | Not MyDevice-仅 -> `fixed` (with an injectable 默认). |
| C4 | "相同-content 冲突 suppression (explicit in MyDevice; verify others)" (P0.1) | **三个应用均** implement it identically: `if (serialize != null && serialize(l) == serialize(r))` (MyAnime `:76`, MyDay `:105`, MyDevice `:97`). 所有 调用点 pass `serialize: (x) => jsonEncode(x.toJson())`. | Not MyDevice-仅 -> `fixed`. |
| C5 | "MyDay's and MyDevice's [mergeRecords] are supersets; MyAnime's is a 子集" (P2.3) | MyAnime's and MyDay's signatures are **字节相同** (8 params). 仅 **MyDevice** is a 超集 - it adds one 可选 param `mergeUnknownFields` (MyDevice `:68`). MyDay is *not* a 超集. | 采用 MyDevice's signature (可选 param is 向后兼容). |
| C6 | "sync_progress.dart (73 行)", "sync_wake_lock.dart (64-65 行)" (PLAN §1) | Both are **62 / 60 行** respectively, 字节相同. | Cosmetic PLAN fix. |
| C7 | "webdav_service.dart: 1855 / 2291 / 2134 行" (PLAN §1) | Actual: **1856 / 2292 / 2135** (off-by-one trailing newline). PLAN's counts were essentially 正确. | Cosmetic. |
| C8 | "Backup format v2 ... `backups/backup_<...>.json` bundles ... `createdAt`" (PLAN §1, P0.1 implies `createdAt`) | The v2 bundle 具有 **否 `createdAt` 字段** and **否 `modules` 字段**. 仅 `_backupFormat` (=2), the 按模块 raw JSON strings, and `_imageRefs` are 写入. `_images` is **旧版 v1 仅** (从不 写入 by v2). | 引擎 must not 写入/读取 `createdAt`; I2 wording updated. |
| C9 | "data_file_safety.dart (MyDay)" 位于 generically | It lives at `lib/shared/services/data_file_safety.dart` (138 行), **not** `lib/shared/utils/`. MyAnime/MyDevice 具有 **否 equivalent file** - their atomic helpers are private inside `BackupService`/`WebDAVService`/the storage hub. | Extraction target: one `lib/src/storage/atomic_io.dart`. |

---

## A. WebDAV 配置与传输

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| A1 | `WebDAVConfig` 字段/types | `serverUrl,username,password,remotePath,autoSync` (`:33`) | 相同 (`:36`) | 相同 (`:36`) | **fixed** |
| A2 | `remotePath` 默认 | `'/MyAnime'` (`:33,80`) | `'/MyDay'` (`:36,83`) | `'/MyDevice'` (`:36,83`) | **config** - 开关 `defaultRemotePath` (按应用 constant) |
| A3 | `.nextcloud()` factory | constructs `https://$host/remote.php/dav/files/$username` (`:89-97`) | 相同 (`:93-101`) | 相同 (`:92-100`) | **fixed** |
| A4 | `isConfigured`/`copyWith`/`toJson`/`fromJson` | 相同 | 相同 | 相同 | **fixed** |
| A5 | Base URL normalization (`_remoteFileUrl`) | strips trailing `/` from serverUrl, ensures remotePath ends `/`, string-concat; **否 URL-encoding** (`:552`) | 相同 (`:733`) | 相同 (`:577`) | **fixed** (latent 否-encoding bug is consistent; 保留 to keep wire-format 字节相同, I1) |
| A6 | `_authHeaders` (HTTP Basic) | `Authorization: Basic <base64>` (`:540`) | 相同 (`:721`) | 相同 (`:565`) | **fixed** |
| A7 | User-Agent | 无 set | 无 | 无 | **fixed** (保留 absence; do not add - changes wire format) |
| A8 | `http.Client` lifecycle | created inline per call, 从不 `.close()`d | 相同 | 相同 | **fixed** (保留; 可选 future hardening out of scope) |
| A9 | `testConnection` verb/depth/body/超时 | PROPFIND Depth:0, 10s (`:567-587`) | 相同 (`:748-768`) | 相同 (`:592-612`) | **fixed** |
| A10 | `testConnection` 可达 statuses | `207 || 404` (`:583`) | `207 || 404` (`:764`) | `207 || 404` (`:608`) | **fixed** (see correction C1) |
| A11 | `_ensureRemoteDir` (MKCOL, swallow 所有) | swallows 所有 errors, 否 405/409 inspect (`:594`) | 相同 (`:775`) | 相同 (`:619`) | **fixed** |
| A12 | `_ensureRemoteSubDir` param/URL | param `subPath`, manual URL rebuild (`:1099`) | param `subPath`, manual rebuild (`:1209`) | param `subDir`, via `_remoteFileUrl` (`:1073`) | **fixed** - unify on `_remoteFileUrl` form (行为 相同) |
| A13 | `_upload` (JSON PUT, 412 handling) | 返回 `({bool is412, String? error})`; 412 msg `'conditional WebDAV PUT failed (HTTP 412)'` (`:615`) | 相同 (`:796`) | 相同 (`:640`) | **fixed** |
| A14 | `_uploadBytes` (图片 PUT) 返回 type | `Future<bool>` (`:669`) | `Future<void>` (`:851`) | `Future<bool>` (`:1023`) | **fixed** - unify on `Future<void>` (返回 value unused) |
| A15 | `_download` (JSON GET) | 返回 `RemoteFile` (`:703`) | 相同 (`:884`) | 相同 (`:698`) | **fixed** |
| A16 | `_downloadBytes` (图片 GET) 返回 type | `Future<Uint8List?>` (`:1027`) | `Future<Uint8List>` (`:1288`) | `Future<Uint8List?>` (`:1053`) | **fixed** - unify on `Future<Uint8List>` (null 从不 actually returned) |
| A17 | `_deleteRemoteUploadLock` 404 early-返回 | 是 (`:788`) | 否 (`:958`) | 否 (`:772`) | **fixed** - drop redundant 404 check (already swallowed) |
| A18 | Per-verb timeouts | PROPFIND-list 15s; PUT-json 30s; PUT-图片 120s; GET-json 30s; GET-图片 120s; MKCOL 10s; DELETE 10s | 相同 **except PROPFIND-list 30s** (`:1258`) | 相同 as MyAnime | **config** - 开关 `propfindTimeout` (默认 15s; MyDay 当前 30s - reconcile to 15s, harmless) |
| A19 | `_dataFileNames` (按应用 file list) | `['anime_data.json']` (`:290`) | 5 files (`:321-327`) | 4 files (`:306-311`) | **config** - 开关 `dataFileNames` (the module registry; replaces the 5 hardcoded MyDay lists, PLAN §1 duplication smell) |
| A20 | `getAppDir()` provider | `AnimeStorage` | `TodoStorage` | `DeviceStorage` | **config** - `StorageAdapter.getAppDir()` (PLAN §3.2) |

---

## B. 上传锁（`WebDAVUploadLock`）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| B1 | 远程 lock file name | `.lock` (`:291`) | `.lock` (`:328`) | `.lock` (`:312`) | **fixed** (I1) |
| B2 | 本地 lock file name | `upload_lock.json` in `.sync_base/` (`:293`) | 相同 (`:330`) | 相同 (`:314`) | **fixed** (I2; see correction C2) |
| B3 | `client_id.txt` in `.sync_base/` | 是 (`:292`) | 是 (`:329`) | 是 (`:313`) | **fixed** |
| B4 | Lock JSON schema | `{clientId, token, startedAt, updatedAt, ttlSeconds}` (UTC ISO8601) (`:190`) | 相同 (`:219`) | 相同 (`:206`) | **fixed** (I1/I2) |
| B5 | TTL | 60s (`_lockTtlSeconds=60`) | 60s | 60s | **fixed** (I3) |
| B6 | Heartbeat | 20s `Timer.periodic`, failures swallowed (`:936`) | 相同 (`:1116`) | 相同 (`:930`) | **fixed** (I3) |
| B7 | Stale-lock takeover | expired 远程 lock replaceable; `If-Match`/`If-None-Match: *` ETag guards (`:832`) | 相同 (`:1012`) | 相同 (`:826`) | **fixed** (I3) |
| B8 | 412 contention message | `'Another device started uploading; retry after the lock expires.'` | 相同 | 相同 | **fixed** (I8) |
| B9 | Interrupted-上传 detection | `_prepareInterruptedUpload`: reads 本地 lock, matches clientId+token against 远程 (`:797`) | 相同 (`:977`) | 相同 (`:791`) | **fixed** (I2) |
| B10 | Lock-写入 重试 exemption | `_writeRemoteUploadLock` passes `retries: 0` (`:768`) | 相同 (`:949`) | 相同 (`:763`) | **fixed** (I3) |
| B11 | `isExpired` rule | `now.difference(updatedAt).inSeconds >= ttlSeconds` (`:203`) | 相同 | 相同 | **fixed** (I3) |

整个上传锁子系统在三个应用之间**字节相同**。它将
原样移入包中；TTL/心跳可注入以便测试，但默认值固定（I3）。

---

## C. PROPFIND XML 解析（唯一真实的传输漂移）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| C-P1 | href regex | `<d:href>` with `caseSensitive:false` (`:1076`) | `<[dD]:href>` char-class, 区分大小写 (`:1265`) | `<(?:\w+:)?href>` prefix-可选, `caseSensitive:false` (`:1115`) | **fixed** - 采用 MyDevice's `<(?:\w+:)?href>` form (most robust: also matches bare `<href>`/`<DAV:href>`) |
| C-P2 | directory-self 跳过 | `endsWith('/')` + `p.basename` | `endsWith('$subPath/')`/`endsWith(subPath)`/`endsWith('/')` + `split('/').last` | `endsWith('/')` + `split('/').last` | **fixed** - unify on `endsWith('/')` + `p.basename` |
| C-P3 | method name | `_listRemoteFiles` (`:1050`) | `_listRemoteDir` (`:1236`) | `_listRemoteFiles` (`:1094`) | **fixed** - unify name |
| C-P4 | PROPFIND listing 超时 | 15s (`:1071`) | 30s (`:1258`) | 15s (`:1109`) | **config** - 开关 `propfindTimeout` (默认 15s); 覆盖 by A18 |

**漂移影响：** MyDevice 最宽松（接受发出无前缀
`<href>` 的服务器）；MyAnime/MyDay 在此类服务器上会静默返回空集合，导致
`_syncImages` 重新上传每个被引用的图片。采用 MyDevice 的正则表达式是安全的，且
严格来说更正确；它不会改变应用当前可正常工作的任何服务器上的行为，
因为所有已知服务器都发出带 `d:`/`D:` 前缀的 href。

---

## D. 重试策略与异常分类

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| D1 | `_withRetry` body | max 2 extra attempts; backoff `Duration(seconds: attemptIndex)` = 1s then 2s (`:342`) | 相同 (`:391`) | 相同 (`:375`) | **fixed** (I3) |
| D2 | retryable exceptions | `SocketException, TimeoutException, http.ClientException, HttpException` | 相同 | 相同 | **fixed** (I3) |
| D3 | retryable status codes | 5xx 仅 via `shouldRetry: (r) => r.statusCode >= 500`; **4xx 从不 retried** | 相同 | 相同 | **fixed** (I3) |
| D4 | operations exempt from 重试 | lock writes (`retries:0`) | 相同 | 相同 | **fixed** (I3) |
| D5 | `RemoteFileStatus` enum | `{found, notFound, error}`; 仅 HTTP 404 -> `notFound` (`:242-285`) | 相同 (`:270-313`) | 相同 (`:257-300`) | **fixed** (仅 true 404 = 缺失) |
| D6 | non-200/404 on 下载 | `RemoteFile.failure('HTTP $code')`; 调用方 abort that file | 相同 | 相同 | **fixed** |

---

## E. 合并引擎（`mergeRecords<T>` 及相关声明）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| E1 | `mergeRecords<T>` signature | 8 params (否 `mergeUnknownFields`) (`:43-52`) | **相同** to MyAnime (`:72-81`) | 9 params: adds 可选 `mergeUnknownFields` (`:61-71`) | **fixed** - 采用 MyDevice's signature (可选 param; 向后兼容). See correction C5. |
| E2 | `RecordConflict<T>` 字段 | `id, localRecord, remoteRecord, displayName` (`:9-12`) | 相同 (`:15-18`) | 相同 (`:13-16`) | **fixed** |
| E3 | `RecordMergeResult<T>` 字段 | `merged, conflicts` (`:29-30`) | 相同 (`:35-36`) | 相同 (`:33-34`) | **fixed** |
| E4 | **Deletion semantics** (see E4 detail) | 相同 | 相同 | 相同 | **fixed** - documented below; pin with tests in P2.3 |
| E5 | 相同-content suppression | `serialize != null && serialize(l)==serialize(r)` -> 否 冲突 (`:76`) | 相同 (`:105`) | 相同 (`:97`) | **fixed** (see correction C4); `serialize` 回调 is the (可选) 开关 |
| E6 | timestamp 字段 | `getModifiedAt` 回调 -> model `modifiedAt` (UTC) | 相同 | 相同 | **fixed**; 开关 is the `getModifiedAt` 回调 |
| E7 | "newer 胜出" | `DateTime.isAfter` 严格 | 相同 | 相同 | **fixed** |
| E8 | ties (equal timestamps, both changed) | 相同-content -> 否 冲突; else `autoResolve`? LWW picks 远程 (`l.isAfter(r) ? l : r`); `autoResolve=false` -> 冲突 | 相同 | 相同 | **fixed** |
| E9 | ties (否 base, equal timestamps) | 远程 胜出 (`? l : r`) | 相同 | 相同 | **fixed** |
| E10 | 缺失/null `modifiedAt` | `DateTime.parse` 抛出 (否 null tolerance) | 相同 | 相同 | **fixed** (document as precondition: `modifiedAt` must be present) |
| E11 | `autoResolve` 默认 | `false` (`:50`); 0 调用点 pass `true` | `false` (`:79`); 0 pass `true` | `false` (`:69`); 0 pass `true` | **fixed** (I4 confirmed) |
| E12 | 按模块 wrappers | `mergeAnimeData` (1 call, 返回 `extraJson`) | 5 wrappers (Todo=2 calls, Finance=4, Intimacy=5, Weight=1, ExchangeRate=custom) | 4 wrappers (Device=1, Network=1+assignments, DataSet=1, Service=2) + `mergeAssignments` | **fixed** - wrappers 保留 应用侧; 包 exports `mergeRecords`/`RecordConflict`/`RecordMergeResult`. `DataModule.merge` 回调 = `(localJson, remoteJson, baseJson, {autoResolve}) -> {mergedJson, conflicts, localChanged, remoteChanged}`. |
| E13 | `mergeExchangeRateJson` (整文件) | 不适用 | custom snapshot union, **否 baseJson, 否 autoResolve, 否 冲突** (`:801-846`) | 不适用 | **fixed** - 保留 应用侧 as a `DataModule.merge` that ignores base/autoResolve |
| E14 | `mergeAssignments` (composite key, 否 timestamps) | 不适用 | 不适用 | composite key `networkId:deviceId`, content-compare vs base, **本地-胜出 on both-changed, 否 冲突 ever** (`:163-220`) | **fixed** - 保留 应用侧 (MyDevice-仅 custom 合并) |

### E4. 记录删除语义（此前未记录，现已固定）

删除逻辑在三个应用中**相同**（MyDevice 例外是
`mergeUnknownFields` 门面）。跟踪于 MyAnime `:103-126` / MyDay `:134-157` /
MyDevice `:127-146`：

| 场景 | 结果 | 冲突? |
|---|---|---|
| 已删除 locally, 远程 未改变 (in base) | **排除** (deletion propagates) | 否 |
| 已删除 locally, 远程 已修改 | **远程 kept** (modify 胜出 over delete) | 否 |
| 已删除 remotely, 本地 未改变 (in base) | **排除** (deletion propagates) | 否 |
| 已删除 remotely, 本地 已修改 | **本地 kept** (modify 胜出 over delete) | 否 |
| 已删除 both sides | **排除** | 否 |
| Pure add on one side (否 base) | **包含** | 否 |
| Both added 相同 id (否 base) | LWW by `modifiedAt` (ties -> 远程) | 否 |

**关键规则：** 删除与修改之间**永远不是冲突**，修改的一方静默胜出。
共享合并测试 `test/sync_merge_test.dart` 已覆盖该行为；本表
记录的是提取时依据，而不是待完成的 P2.3 任务。上面的 MyDay 行号引用
指向提取前实现。

---

## F. 未知 JSON 字段保留（I6）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| F1 | 保留 style | baked into models: `extraJson` + `withPreservedUnknownJson` + `_mergeJsonMaps` (e.g. `anime.dart:377,775-814`) | schema-driven 引擎 `JsonPreservation` (`json_preservation.dart:1-251` generic; `:252-619` app schemas) | model `extraJson` + `mergeUnknownFields`/`mergeUnknownFieldsFrom` (`json_preservation.dart` 81 行, generic 仅) | **config** - 包 exports BOTH: (a) `mergeUnknownFields` 回调 on `mergeRecords` (MyDevice pattern, for model-level `extraJson` apps); (b) MyDay's generic `JsonPreservation` 引擎 (行 1-251) as `lib/src/json/json_preservation.dart` for schema-driven re-injection. App schemas 保留 应用侧. |
| F2 | 合并 self-sufficient for 保留? | 是 (per-record `withPreservedUnknownJson`) | **否** - 合并 operates on typed objects, unknowns lost at 合并; re-injected at 写入 time by `webdav_service._preserveUnknownJson` (`:614-628`) | 是 (`mergeUnknownFields` 回调) | **config/行为** - 保留 remains 应用侧: MyDay re-applies its schemas at 写入 time, while MyAnime/MyDevice 使用 model-level 回调. The extracted 引擎 does not assume 合并 is self-sufficient. |
| F3 | round-trip survival (parse->合并->写入) | full | full (仅 via the 写入时 re-injection) | full | **fixed** (I6 holds 今天; 保留) |
| F4 | MyDay generic 引擎 API | 不适用 | `JsonListPreservation`, `JsonPreservationSchema`, `JsonPreservation` (static: `encodeForFile`, `preserveJsonString`, `preserve`, `_preserveOne`, ...) | 不适用 | **fixed** - 移入 行 1-251 原样 to 包; app schemas (`_todoDataSchema` etc.) 保留 应用侧 |
| F5 | MyDevice 保留 API | 不适用 | 不适用 | `unknownJsonFields`, `mergeUnknownJsonFields`, `jsonValueEquals` (`:8,21,64`) | **fixed** - 移入 to 包 (overlaps with F1(b)) |

---

## G. 同步编排

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| G1 | `sync()` step order | ensureRemoteDir -> getAppDir -> loadClientId -> prepareInterruptedUpload -> **acquire lock** -> 按文件 下载/migrate/合并/上传 -> 图片 sync -> release lock (`:1252`) | 相同 (`:1471`) | 相同 (`:1276`) | **fixed** (lock acquired BEFORE downloads; 保留) |
| G2 | `autoResolve` at sync | 默认 `false`, 否 caller overrides (`:1254`) | 相同 (`:1473`) | 相同 (`:1278`) | **fixed** (I4) |
| G3 | 下载-错误 handling | **aborts 整个 sync** (`:1355`) | 按文件 `perFileErrors.add` + `continue` (`:1582`) | 按文件 (`:1384`) | **config** - 开关 `failFastOnDownloadError` (包 默认 `false`; MyAnime was `true` at the audit baseline but had one module). The extracted facades 使用 the 包 默认. |
| G4 | 按文件 合并 try/catch | 无 (single file) | `try{switch(name){...}}catch(e){perFileErrors.add('$name: $e')}` (`:1644-1851`) | 相同 (`:1438-1641`) | **fixed** - generalize 按文件 guard |
| G5 | top-level catch format | `'$e\n$st'` (stack trace) (`:1495`) | `e.toString()` (否 trace) (`:1895`) | `'$e\n$st'` (`:1684`) | **fixed** - unify on stack-trace form (reconcile MyDay) |
| G6 | 按文件 错误 string | 不适用 (single file) | `'$name: $e'` | `'$name: $e'` | **fixed** |
| G7 | MyDay finance migration hook | 不适用 | async `_migrateFinanceForcedBalances` after 冲突-free 合并/解决方案 and during finalize (`:424,1740,1941`); it reads 本地 exchange-rate storage | 不适用 | **config** - 开关 `postMergeTransform` on `DataModule`; applied after 合并/解决方案, not to 远程 JSON before 冲突 detection |
| G8 | MyDay 未知-JSON re-injection at 写入 | model-level 仅 | `_preserveUnknownJson`/`_uploadMergedJson` (`:614,679`) | model-level 仅 | **config** - 覆盖 by F2; 引擎 提供 a `preUploadTransform` hook |

### G-IMG. 图片同步

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| G9 | referenced-图片 来源 | anime `coverImage` basenames (`:1122-1134`) | finance `accounts`+`subscriptions` + intimacy `partners`+`toys` `imagePath` (`:1313-1344`) | device `imagePath` basenames (`:1138-1152`) | **config** - 开关 `referencedImages` 回调 on `DataModule` (PLAN §3.2) |
| G10 | 本地 ∪ 远程 union | union of 本地+远程 referenced (`:1474`) | 相同 (`:1856`) | 相同 (`:1646`) | **fixed** |
| G11 | additive-仅 (从不 delete) | 是 - 否 delete path | 是 | 是 | **fixed** (I1) |
| G12 | orphan handling | skipped, 从不 已删除, 从不 uploaded (`:1157-1164`) | 相同 (`:1369-1376`) | 相同 (`:1181-1188`) | **fixed** |
| G13 | 远程 `images/` subdir | literal `'images'` (`:1155`) | 相同 (`:1367`) | 相同 (`:1179`) | **fixed** (I1) |
| G14 | 图片 警告 strings (I8) | 字节相同 set (see §N) | 相同 | 相同 | **fixed** |

### G-FORCE. forceUpload / forceDownload

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| G15 | `forceUpload` rewrites `.sync_base` | 是 - `_saveBase(name, localRaw)` after each 上传 (`:1639`) | 是 (`:2071`) | 是 (`:1918`) | **fixed** (I2) |
| G16 | `forceUpload` disables autoSync? | 否 (仅 `_syncing` guard) | 否 | 否 | **fixed** (保留; confirmation dialog suffices) |
| G17 | `forceUpload` wake-lock | 是 (page acquires/releases) | 是 | 是 | **fixed** |
| G18 | `forceUpload` skips 未改变? | 否 - uploads 所有 existing files | 否 | 否 | **fixed** |
| G19 | `forceDownload` rewrites `.sync_base` | 是 (`:1785`) | 是 (`:2222`) | 是 (`:2064`) | **fixed** (I2) |
| G20 | `forceDownload` disables autoSync? | 否 (下载-仅, 否 lock) | 否 | 否 | **fixed** |
| G21 | `forceDownload` wake-lock | 是 | 是 | 是 | **fixed** |
| G22 | `forceDownload` 校验 | `jsonDecode(remoteRaw)` 仅 (`:1781`) | 相同 (`:2218`) | 相同 (`:2060`) | **fixed** (jsonDecode-仅; consider `DataModule.validate` hook - 相同 as G24) |
| G23 | `forceDownload` 缺失-远程 string | `'$name: not found on remote; local file kept'` (`:1772`) | 相同 (`:2209`) | 相同 (`:2051`) | **fixed** (I8) |

### G-FIN. finalizePendingSync 与冲突流程

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| G24 | `PendingSync` shape | `{AnimeMergeResult? animeMerge}`; `allConflicts: List<RecordConflict<Anime>>` | 4 合并 字段; `allConflicts` untyped (`:138-175`) | 4 合并 字段; `allConflicts` untyped (`:133-162`) | **config** - 按应用 `PendingSync`/`allConflicts` types 保留 应用侧 (facades rebuild app-typed shapes); 引擎 treats 冲突 as opaque records (PLAN §3.3) |
| G25 | 解决方案 map type | `Map<String, Anime>` (typed) (`:1508`) | `Map<String, dynamic>` (`:1909`) | `Map<String, dynamic>` (`:1727`) | **fixed** - 引擎 signature `finalizePendingSync(pending, Map<String,dynamic>)` + per-合并 type-filter (MyDevice pattern) |
| G26 | finalize re-downloads 远程? | **否** - writes+uploads directly (`:1527`) | **是** - for 保留 (`_finalizeFile`) | **是** - + aborts file on 错误 (`_finalizeFile`) | **fixed** - standardize on MyDevice's re-下载-then-abort-on-错误 (race-安全) |
| G27 | 冲突-cancel abort (v1.2.1) | cancel -> 本地 未改变, nothing uploaded, 冲突 保留 pending, 否 wake-lock, 否 `.lock` held | 相同 (single dialog) | 相同 (per-冲突 dialog) | **fixed** (I4; v1.2.1 semantics preserved) |
| G28 | 冲突 dialog topology | one `_ConflictDialog` per 冲突 (sequential) | single `SyncConflictDialog` for 所有 | one `_ConflictDialog` per 冲突 | **config** - UI 保留 按应用 (非目标); 引擎 semantics 相同 |

### G-MISC. consumeLocalDataChanged 与 SyncProgress

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| G29 | `consumeLocalDataChanged` mechanism | `static bool _localDataChanged`; 读取-and-reset (`:305,375`) | 相同 (`:342,350`) | 相同 (`:326,334`) | **fixed** |
| G30 | set by | sync writes (下载/合并/finalize/图片/forceDownload) | 相同 (more sites = more modules) | 相同 | **fixed** (semantics 相同; count differs 仅 by module count) |
| G31 | consumed by | `AutoSyncService._trySync` + `notifyLocalDataChangedIfNeeded` | 相同 | 相同 | **fixed** |
| G32 | `notifySaved` (separate signal) | 是 - storage `save()` -> `AutoSyncService.notifySaved()` -> 30s debounce; NOT `_localDataChanged` | 是 | 是 | **fixed** (do not conflate the two signals) |
| G33 | `SyncProgress` phase order | `connecting -> downloadingData -> merging -> uploadingData -> uploadingImages -> downloadingImages -> done|error` | 相同 | 相同 | **fixed** (字节相同 file; see §0) |
| G34 | merged-上传 progress count | module index / module total | structured modules report `0/0` through `_uploadMergedJson`; exchange rates and raw 本地-仅 uploads 使用 module index/total | module index / module total | **config** - `DataModule.indexMergedUploadProgress` (默认 true; false for MyDay todo/finance/intimacy/weight) |

---

## H. 自动同步调度器（`auto_sync_service.dart`）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| H1 | sync triggers | launch / resume / 15-min timer / 30s-debounce / config-save (`:163-216`) | 相同 (`:173-223`) | 相同 (`:169-222`) | **fixed** |
| H2 | debounce duration | 30s (`:28`) | 30s (`:33`) | 30s (`:32`) | **fixed** |
| H3 | lifecycle observer | `WidgetsBindingObserver`, acts on `resumed` 仅 | 相同 | 相同 | **fixed** |
| H4 | calls `WebDAVService.sync(config)` without `autoResolve` | 是 (`:233`) | 是 (`:241`) | 是 (`:240`) | **fixed** (I4) |
| H5 | **backup trigger 来源** | `AutoSyncService` 15-min + resume (`:164-167,215-219`) | **`ReminderService` 30s loop** (`reminder_service.dart:85,608`) - AutoSyncService does NOT call backup | `AutoSyncService` 15-min + resume (`:170-173,221-224`) | **config** - 非目标: 保留 MyDay's ReminderService-driven backup (PLAN 非目标). 包 提供 `runAutoBackupIfNeeded()`; host owns the trigger. |
| H6 | resume side-effects | + reminders + backup | + mobile reminder refresh | + backup 仅 | **config** - injectable `onResume` hooks (app-specific) |
| H7 | test seam | `appDirProvider` on `BackupService`, **not** AutoSyncService (`:44`) | 相同 (`:46`) | 相同 (`:47`) | **fixed** (保留 `appDirProvider` on backup; add injectable storage provider to 共享 `WebDAVService` for testability) |

> **PLAN 注释已修正：** PLAN 将 `appDirProvider` 测试接缝归因于
> `AutoSyncService`；实际上它在三个应用的 `BackupService` 中。
> `@visibleForTesting static Future<Directory> Function()? appDirProvider` 会将所有
> 备份 I/O 重定向到测试目录。

---

## I. `.sync_base` 快照（I2）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| I-S1 | 布局 | one file per module mirroring data-file names + `client_id.txt` + `upload_lock.json` | 相同 (5 module files) | 相同 (4 module files) | **fixed** (I2) |
| I-S2 | 写入 when | after successful 合并+上传 / 下载-仅 / 本地-仅 force-上传 / 相同 fast-path / forceUpload / forceDownload / finalize | 相同 | 相同 | **fixed** (I2) |
| I-S3 | NOT 写入 when | 合并 上传 failure / finalize 上传 failure / 冲突 (否 上传) / 下载 错误 | 相同 | 相同 | **fixed** (I2) |
| I-S4 | 原子性 | `_saveBase` -> `_atomicWrite` (tmp-rename) | 相同 | 相同 | **fixed** |

---

## J. 备份引擎（`backup_service.dart`）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| J1 | `modules` map (fileName -> moduleId) | `{'anime_data.json':'anime'}` (`:48`) | 5 entries: `todo, finance, exchangeRates, intimacy, weight` (`:50-56`) | 4 entries: `devices, networks, datasets, services` (`:51-56`) | **config** - 开关 `modules` (按应用 registry; preserves existing ids for back-compat, I2) |
| J2 | moduleId naming | singular lowercase | singular lowercase **except** `exchangeRates` (camelCase) | **plural** lowercase | **config** - preserved 原样 per app (do not rename; would break I2). Document the inconsistency. |
| J3 | synthetic `images` backup module | absent (images 始终 restore) | absent (images 始终 restore) | present, restore-selectable (`:362-377,444`) | **config** - 开关 `syntheticImagesModule` (MyDevice=true; others=false). OR standardize on `true` for 所有 (more explicit/safer). |
| J4 | `_backupFormat` value | `2` (`_formatVersion=2`) | `2` | `2` | **fixed** (I2) |
| J5 | v2 bundle top-level 字段 | `_backupFormat` + 按模块 raw JSON strings + `_imageRefs` (when images) | 相同 | 相同 | **fixed** (I2; see correction C8 - 否 `createdAt`, 否 `modules`) |
| J6 | `_imageRefs` shape | `Map<'images/<name>','<sha256><ext>'>` (`:203-207`) | 相同 (`:165-169`) | 相同 (`:233-237`) | **fixed** |
| J7 | `_images` (旧版 v1) | 只读 on restore (`:424-435`); 从不 写入 by v2 | 相同 (`:395-406`) | 相同 (`:469-480`) | **fixed** (I2) |
| J8 | blob store | `backups/blobs/<sha256><ext>`; sha256 of 原始字节; ext from `p.extension`; dedup via exists-check (`:187-200`) | 相同 | 相同 | **fixed** |
| J9 | GC grace | `Duration(minutes: 10)` (`:32`) | 相同 (`:32`) | 相同 (`:35`) | **config** - 开关 `blobGcGrace` (默认 10 min) |
| J10 | GC abort-on-unparseable | `return` (整个 pass aborts) (`:508-511`) | 相同 (`:481-484`) | 相同 (`:554-557`) | **fixed** |
| J11 | retention 默认 | `0` (永久) (`:35,97`) | `0` (`:36,107`) | `0` (`:38,105`) | **fixed** |
| J12 | `_probeMaxBytes` | `4 * 1024 * 1024` (`:28`) | 相同 (`:28`) | 相同 (`:31`) | **config** - 开关 `probeMaxBytes` (默认 4 MiB); see correction C3 |
| J13 | `listBackups` 损坏 handling | flagged `corrupt=true`, skipped (not thrown) (`:308-310`) | 相同 (`:276-278`) | 相同 (`:338-340`) | **fixed** |
| J14 | "already backed up 今天" 损坏 | `if (b.corrupt) return false` (损坏 doesn't count) (`:244`) | 相同 (`:210`) | 相同 (`:274`) | **fixed** |
| J15 | "今天" check 来源 | `listBackups()` filename date; in-memory `_lastAutoBackup` (否 persisted `lastBackupAt`) (`:242-249`) | 相同 (`:208-215`) | 相同 (`:272-279`) | **fixed** (do NOT add `lastBackupAt` to storage_config) |
| J16 | `RestoreResult` 字段 | `{ok, wroteAnything, missingImages}` (`:533-550`) | 相同 (`:506-523`) | 相同 (`:579-596`) | **fixed** |
| J17 | v1 图片-key sanitization | `_safeImageRelativePath` (requires `images/` prefix, 2 segments) (`:350-359`) | 相同 (`:319-328`) | `_safeImageBasename` (accepts bare + prefixed) (`:386-398`) | **config/行为** - standardize on MyDevice's 宽松 `_safeImageBasename` (向后兼容 with 旧版 bare-key bundles in 所有 apps) |
| J18 | I5 autoSync interplay (restore) | disable before 第一 写入; re-enable iff `!wroteAnything` (in `backup_page.dart:137-162`) | 相同 (`:189-214`) | 相同 (`:135-160`) | **fixed** (I5; 相同 in 三个应用均) |
| J19 | post-restore reminder refresh | `ReminderService.notifyDataChanged()` | `ReminderService.instance.refreshMobileSchedules()` | 无 (否 reminders) | **config** - injectable post-restore hook |
| J20 | `appDirProvider` test seam | `@visibleForTesting static ...? appDirProvider` (`:44`) | 相同 (`:46`) | 相同 (`:47`) | **fixed** (保留 as the test override) |
| J21 | backup trigger cadence | AutoSyncService 15-min + launch + resume | ReminderService 30s loop | AutoSyncService 15-min + launch + resume | **config** - 覆盖 by H5 (host owns trigger) |

---

## K. 原子 I/O 与校验分发

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| K1 | atomic helper location | 重复: `AnimeStorage._atomicWrite` (fixed `.tmp`!) + `BackupService._atomicWriteString/Bytes` | 集中式: `DataFileSafety.atomicWriteString/Bytes` (`data_file_safety.dart:96-137`) | 重复: 仅 `BackupService._atomicWriteString/Bytes` | **fixed** - one `lib/src/storage/atomic_io.dart` |
| K2 | tmp naming | mixed: fixed `.tmp` (AnimeStorage, concurrency hazard) vs 唯一 `.tmp-<microseconds>` (BackupService) | 唯一 `.tmp-<microseconds>` | 唯一 `.tmp-<microseconds>` | **fixed** - 唯一 `.tmp-<microsecondsSinceEpoch>` |
| K3 | cleanup on failure | BackupService 是; AnimeStorage **否** (orphans tmp) | 是 | 是 | **fixed** - cleanup-on-failure 始终 |
| K4 | 错误 wrap | 无 | `FileSystemException('Failed to replace file safely: $e', file.path)` | 无 | **fixed** - 采用 MyDay's `FileSystemException` wrap |
| K5 | fsync | 无 (flush 仅) | 无 | 无 | **fixed** (保留; 可选 future `fsync` bool, 默认 false) |
| K6 | `DeviceStorage.save()` atomic? | 不适用 | 不适用 | **否** - plain `writeAsString` (`device_storage.dart:240`) | **行为** - remains an 应用侧 durability gap outside this 包; the extracted 包's `StorageAdapter` does not silently change `DeviceStorage.save()` semantics. |
| K7 | per-storage 写入 queue | 否 (AnimeStorage fixed-tmp hazard) | 是 (`TodoStorage._writeQueue` serializes saves, `:141`) | 否 | **config** - 可选 按文件 写入 queue (MyDay pattern); at minimum fix AnimeStorage's fixed-tmp |
| K8 | 校验 dispatch (pre-写入) | inline `AnimeData.fromJson` in restore (`:391`) | 集中式 `DataFileSafety.validateDataJson` (switch on fileName, typed `DataFileValidationException`) (`:53-76`) | `BackupService._validateModuleJson` (switch, `FormatException`) (`:126-140`) | **fixed** - `DataModule.validate(String)` interface; reuse MyDay's typed `DataFileValidationException` |
| K9 | 校验 共享 with save path? | 否 | 是 (TodoStorage._saveNow -> writeValidatedDataJson) | 否 (save unvalidated + non-atomic) | **行为** - route data saves through `validate`+`atomicWrite` (MyDay pattern) |

---

## L. `storage_config.json` 键（I2）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| L1 | `autoBackupEnabled` | exact (`:96,107`) | exact (`:106`) | exact (`:104,115`) | **fixed** (I2) |
| L2 | `backupRetentionDays` | exact (`:97,108`) | exact (`:107`) | exact (`:105,116`) | **fixed** (I2) |
| L3 | `lastBackupAt` | absent | absent | absent | **fixed** (keep absent; see J15) |
| L4 | `storagePath` | `anime_storage.dart:61,123` | `todo_storage.dart:250,283` | `device_storage.dart:63,113` | **fixed** (共享 key; StorageAdapter) |
| L5 | locale key | `locale` | **`localeTag`** | `locale` | **config/行为** - standardize on `locale` (migrate MyDay off `localeTag`); flag for I2 |
| L6 | `saveSettings` 写入 semantics | replace (atomic) | 合并 (non-atomic) | replace (non-atomic) | **fixed** - 合并-写入 + atomic (combine both) |
| L7 | API port 默认 | 7788 | 7790 | 7789 | **config** - 按应用 默认 (host-injected); out of extraction scope (本地_api_server 保留 应用侧) |
| L8 | other keys | themeMode, weekStartDay, homeCalendar*, minimizeToTray, reminder*, api* | themeMode, weekStartDay, intimacy*, minimizeToTray, reminderNotifiedKeys, api* | themeMode, minimizeToTray, api*, defaultCurrency, sortMode* | **fixed** - 所有 保留 应用侧 (not touched by extraction; StorageAdapter 仅 owns backup+storage keys) |

---

## M. ZIP 导入/导出（`import_export_service.dart`）

| # | 行为点 | MyAnime | MyDay | MyDevice | 判定 |
|---|---|---|---|---|---|
| M1 | archive name prefix | `myanime_export_` (`:42-43`) | `myday_backup_` (`:50-51`) | `mydevice_export_` (`:61-62`) | **config** - 开关 `archiveNamePrefix` + `archiveNameVerb` (or one `archiveNamePattern` template) |
| M2 | timestamp format + ext | `yyyyMMdd_HHmmss` + `.zip` | 相同 | 相同 | **fixed** |
| M3 | 导出 entry 允许列表 | hardcoded `anime_data.json` + `images/*` (`:22-38`) | from `_dataFileNames` (5) + `images/*` (`:12-18`) | from `_dataFileNames` (4) + `images/*` (`:19-24`) | **config** - 开关 `dataFileNames` (the registry; 覆盖 by A19) |
| M4 | 从不 bundles | `storage_config.json`, `webdav_config.json`, `.sync_base/`, `backups/`, manifest | 相同 | 相同 | **fixed** |
| M5 | images in 导出 | `images/<basename>` blobs | 相同 | 相同 | **fixed** |
| M6 | path-traversal rejection | `p.normalize` + `..` substring + `p.isWithin`; **skips** (`continue`) (`:70-80`) | `p.url.normalize` + `../`&`/../` substring + `_isInside`; **rejects** (`return false`) (`:77-80,124-128`) | `p.normalize` + `..` + `p.isWithin`; **skips** (`:88-101`) | **fixed** - standardize on `p.url.normalize` + **拒绝** (`return false`) (MyDay, safest) |
| M7 | 未知-entry handling | 跳过 (`continue`) | 拒绝 (`return false`) | 跳过 (`continue`) | **config** - 开关 `rejectUnknownEntries` (默认 `true` = MyDay) |
| M8 | UTF-8 strictness | 无 - 原始字节 (`:87`) | **严格 `utf8.decode`** (抛出 -> `return false`) (`:83-84`) | 无 - 原始字节 (`:106`) | **config** - 开关 `strictUtf8` (默认 `true` = MyDay) |
| M9 | pre-写入 校验 | 无 | 2-phase: `validateDataJson` (jsonDecode + model `.fromJson`) for 所有 entries before writing ANY, then atomic 写入 (`:82-111`) | 无 | **config** - 开关 `validateBeforeWrite` + `atomicWrites` (默认 `true` = MyDay); validator injected via `DataModule.validate` |
| M10 | 导入 target | `appDir`, `writeAsBytes` 覆盖; 否 re-sync/backup (`:66,77-87`) | `appDir`, atomic 覆盖; 否 re-sync/backup (`:70,101-111`) | `appDir`, `writeAsBytes` 覆盖; 否 re-sync/backup (`:84,95-106`) | **fixed** (target = appDir, 覆盖); expose 可选 `onAfterImport` hook (当前 否 app disables auto-sync on 导入 - latent gap, flagged) |
| M11 | `flush: true` on 导出 写入 | 否 | 是 (`:52`) | 否 | **fixed** - 采用 `flush: true` (minor robustness) |
| M12 | public API | `exportZIP(String)->Future<String?>`, `importZIP(String)->Future<bool>` (`:17,59`) | 相同 (`:25,64`) | `exportZip`/`importZip` (camelCase) (`:33,77`) | **fixed** - standardize casing `exportZip`/`importZip` (ZipTransfer facade) |
| M13 | `package:archive` usage | `ZipEncoder().encode` / `ZipDecoder().decodeBytes`; 默认 level; 否 encryption | 相同 | 相同 | **fixed** |
| M14 | Markdown 导出 | `exportMarkdown` in-file (`:102`); `myanime_export_<stamp>.md` | **无** | `exportMarkdown` + pure `buildMarkdown` (`:122,150`); `mydevice_export_<stamp>.md` | **非目标** - 保留 应用侧 (not extracted) |
| M15 | 保留 引擎 in 导入? | 否 (原始字节; survives trivially) | 否 (保留 via model `extraJson` during 校验, not the 引擎) | 否 (原始字节) | **fixed** - facade does not invoke 保留; app validator handles it |

> **建议的门面默认值 = MyDay 的严格行为** (`strictUtf8`、
> `validateBeforeWrite`、`atomicWrites`、`rejectUnknownEntries`、`rejectOnTraversal`、
> `p.url.normalize`、`flushOnWrite`) —最安全且最新的加固（v1.1.3/v1.2.5）。
> 如需保留旧版的宽松行为，请将布尔值关闭。

---

## N. 用户可见字符串（I8）——待协调的漂移

共享服务会将字符串写入 `SyncResult.error`、`SyncResult.warnings` 以及
备份/ZIP 结果路径。大多数同步/图片字符串已经字节相同，只有少量
存在漂移，需协调为一组共享字符串（I8 要求字节相同）。

### N1. 三个应用均已字节相同（保留为共享常量）

```
'Sync already in progress'
'Upload lock was not acquired'                      (NOTE: MyDay also has lowercase variant - see N2)
'Another device is uploading; retry after the lock expires.'
'Another device started uploading; retry after the lock expires.'
'conditional WebDAV PUT failed (HTTP 412)'
'Image sync skipped: could not list the remote images directory'
'Image download skipped: could not list the remote images directory'
'Upload skipped for $name: upload lock was not acquired'
'Upload timed out: $name'
'Upload failed for $name: $e'
'Download timed out: $name'
'Download failed for $name: $e'
'$name: not found on remote; local file kept'
'$name: remote content is not valid JSON'
'Failed to force-upload $name: ${uploadResult.error}'
'Failed to download $name from remote: ${remote.error}'
'HTTP ${response.statusCode}'
```

### N2. 字符串漂移（必须选择一个，建议见最后一列）

| # | String | MyAnime | MyDay | MyDevice | Reconcile to |
|---|---|---|---|---|---|
| N2a | lock-not-acquired (one path) | `'Upload lock was not acquired'` (capitalized) | `'upload lock was not acquired'` (lowercase, `:700`) | capitalized | **capitalized** (fix MyDay) |
| N2b | 按文件 下载 错误 (sync) | `'Failed to download $name from remote: ${remote.error}'` (`:1358`) | `'$name: download failed: ${remote.error}'` (`:1583`) | `'$name: download failed: ${remote.error}'` (`:1385`) | **`'$name: download failed: ${remote.error}'`** (fix MyAnime - 2 of 3 使用 it; aligns with 按文件 pattern) |
| N2c | 按文件 force-上传 failure | `'Failed to force-upload merged $name under WebDAV lock: ...'` / `'Failed to force-upload $name under WebDAV lock: ...'` (`:1393,1462`) | `'$name: force-upload failed: ${result.error}'` / `'$name: upload failed: ...'` (exchange-rates, `:1666`) | `'$name: force-upload failed: ${uploadResult.error}'` (`:1417,...`) | **`'$name: force-upload failed: ${result.error}'`** (fix MyAnime; drop MyDay's exchange-rates-仅 variant) |
| N2d | 按文件 合并 catch | 无 (single file, aborts) | `'$name: $e'` (`:1850`) | `'$name: $e'` (`:1640`) | **`'$name: $e'`** (generalize 按文件) |
| N2e | top-level catch | `'$e\n$st'` (stack trace) (`:1495`) | `e.toString()` (否 trace) (`:1895`) | `'$e\n$st'` (`:1684`) | **`'$e\n$st'`** (fix MyDay - stack trace aids diagnosis) |
| N2f | 按文件 错误 join | 不适用 | `perFileErrors.join('; ')` | `perFileErrors.join('; ')` | **`'; '`** join (fixed) |

### N3. 备份/ZIP UI 字符串（l10n 保留在应用侧，但应统一键集合）

`backup_service.dart`/`import_export_service.dart` 本身**不包含**用户可见字符串字面量；
结果为 `{ok, wroteAnything, missingImages}` / `String?` / `bool`，
所有文本都在页面组件中通过 `AppLocalizations` 拼接。l10n **键
名称** 存在漂移（例如 MyDay 的 `backupRestoreSuccess` 与 MyAnime/MyDevice 的 `backupRestored`；
MyDay 的 `commonCancel` 与其他应用的 `cancel`；MyDay 拆分 `*Title`/`*Desc`）。由于 UI 是
非目标（不提取），这些仍由各应用自行维护。**仅建议：**未来 l10n 过程统一
使用 MyDay 的 `*Title`/`*Desc` 拆分和 `backupRestored` 键；当前不阻塞。

### N4. 冲突 `displayName`（源自数据，不做本地化）

`getDisplayName` 回调产生非本地化、源自数据的字符串（例如
`'${t.emoji ?? ''} ${t.title}'.trim()`）。这些字符串原样传入冲突对话框，
由调用方提供，因此仍由应用侧负责（`DataModule.merge` 回调拥有它们）。
不会有 i18n 字符串移入包中。

---

## O. 汇总配置开关（列出的 `config` 行）

这些是共享引擎对外暴露的按应用注入点。未列出的内容都是 `fixed`（一个共享实现）。
here is `fixed` (one 共享 实现).

| 开关 | 类型 | 来源 | 默认 | PLAN 抽象 |
|---|---|---|---|---|
| `defaultRemotePath` | `String` | A2 | 按应用 (`/MyAnime`,`/MyDay`,`/MyDevice`) | `WebDavSyncEngine` ctor |
| `dataFileNames` | `List<String>` | A19, M3 | 按应用 module list | `ModuleRegistry` |
| `getAppDir` | `Directory Function()` | A20 | 按应用 storage hub | `StorageAdapter.getAppDir()` |
| `modules` (fileName->moduleId) | `Map<String,String>` | J1 | 按应用 | `ModuleRegistry` |
| `referencedImages` | `Set<String> Function(String json)?` | G9 | 按应用 extractor | `DataModule.referencedImages` |
| `merge` | 回调 | E12 | 按应用 wrapper | `DataModule.merge` |
| `validate` | `void Function(String json)` | K8 | 按应用 parser | `DataModule.validate` |
| `postMergeTransform` | `FutureOr<String> Function(String)?` | G7 | 按应用 (MyDay finance) | `DataModule.postMergeTransform` |
| `syntheticImagesModule` | `bool` | J3 | false (MyDevice=true) | `BackupEngine` ctor |
| `propfindTimeout` | `Duration` | A18, C-P4 | 15s | `WebDavClient` ctor |
| `blobGcGrace` | `Duration` | J9 | 10 min | `BackupEngine` ctor |
| `probeMaxBytes` | `int` | J12 | 4 MiB | `BackupEngine` ctor |
| `failFastOnDownloadError` | `bool` | G3 | false | `WebDavSyncEngine` ctor |
| `archiveNamePrefix` + `archiveNameVerb` | `String`+`String` | M1 | 按应用 | `ZipTransfer` ctor |
| `strictUtf8` | `bool` | M8 | true | `ZipTransfer` ctor |
| `validateBeforeWrite` | `bool` | M9 | true | `ZipTransfer` ctor |
| `atomicWrites` | `bool` | M9 | true | `ZipTransfer` ctor |
| `rejectUnknownEntries` | `bool` | M7 | true | `ZipTransfer` ctor |
| `onAfterImport` | 回调 | M10 | null | `ZipTransfer` |
| `onResume` hooks | 回调 | H6 | 按应用 | `AutoSyncScheduler` |
| `preUploadTransform` / 保留 | 回调 | G8, F2 | 按应用 | `DataModule` / 引擎 hook |
| `indexMergedUploadProgress` | `bool` | G34 | true (false for MyDay structured modules) | `DataModule` |
| 旧版 图片-key tolerance | 行为 | J17 | 宽松 | `BackupEngine` (standardize on `_safeImageBasename`) |
| locale config key | `String` | L5 | `locale` | 应用侧 migration (MyDay) |

---

## P. 待解决问题

**没有待解决问题。** 下方已解决每个 P0.1 条目（PLAN 明确提出的问题
均已回答；没有新的未知项会阻塞 Phase 2）：

| PLAN open 问题 | 解决方案 | Row |
|---|---|---|
| `testConnection` statuses - do the others treat 207+404? | 是 - 三个应用均 相同 | C1, A10 |
| 本地 `.sync_base/upload_lock.json` - MyAnime/MyDevice equivalents? | 是 - 三个应用均 具有 it | C2, B2 |
| PROPFIND parsing - align exactly? | Three regexes; 采用 MyDevice's `<(?:\w+:)?href>` | C-P1 |
| Record deletion semantics (not captured) | Pinned in E4 detail; 相同 across 三个应用均 | E4 |
| 相同-content suppression - verify others? | 三个应用均 相同 | C4, E5 |
| 图片 sync referenced-name sources - confirm MyDevice? | device `imagePath` basenames | G9 |
| `_probeMaxBytes` - others? | 三个应用均 具有 4 MiB | C3, J12 |
| `storage_config.json` key spelling (`autoBackupEnabled`,`backupRetentionDays`)? | 相同 in 三个应用均 | L1, L2 |
| ZIP archive name prefixes - capture exact MyAnime? | `myanime_export_` | M1 |
| `mergeRecords` supersets - confirm MyAnime 子集? | MyAnime==MyDay; 仅 MyDevice is 超集 | C5, E1 |
| `createdAt` in v2 bundle? | Absent (PLAN wording 已修正) | C8, J5 |
| `_imageRefs`/`_images` 字段 names? | `_imageRefs` (v2), `_images` (v1 旧版 仅) | J5-J7 |

---

## Q. 本矩阵的验证

- 通过 `git diff --no-index` 和 SHA-256 哈希比对：`sync_progress.dart`、
  `sync_wake_lock.dart` 已确认字节相同（退出码 0）。
- 其他文件均已在三个应用中完整阅读；每一行行为记录都引用
  `file:line` 行号，可在以下工作树中验证：
  `C:\Users\yuanzhe\source\repos\{MyAnime,MyDay,MyDevice}`（HEAD 为 2026-07-23 状态）。
- 每一行都标记为 `fixed` 或 `config`；每个 `config` 行都指明了开关（见§O）。
- 待解决问题：无（见§P）。
- 本审计促成了 P2.5（WebDAV 客户端）、P2.3（合并）、P2.6（同步）、
  P2.7（备份）、P2.8（ZIP）和 P0.2 黄金测试框架的实现。当前
  行为由包源码和测试验证，而不是通过重新运行
  已退役的提取计划。
