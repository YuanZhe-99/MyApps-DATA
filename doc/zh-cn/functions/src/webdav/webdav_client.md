# lib/src/webdav/webdav_client.dart

纯 WebDAV 传输客户端——动词、认证、重试、远程锁原语和心跳机制。不访问本地文件系统。这是 P2.5 的交付物（feature-matrix §A–§D、§B、§C）。所有超时、TTL、心跳和重试退避都可为测试注入，默认值固定为应用当前的值（I3）。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| [`RemoteFileStatus`](#remotefilestatus-enum) | 枚举 | A | 一次下载尝试的结果状态（found/notFound/error）。 |
| [`RemoteFile`](#remotefile-class) | 类 | A | 判别式下载结果，把 404 与错误区分开（§D5–D6）。 |
| [`WebDavClient`](#webdavclient-class) | 类 | A | 纯 WebDAV 传输：动词、认证、重试、远程锁原语、心跳。 |

## 文档

### `RemoteFileStatus` 枚举 <a id="remotefilestatus-enum"></a>

- **来源：** `lib/src/webdav/webdav_client.dart`。
- **值：** `found`、`notFound`、`error`。
- **用途：** 区分下载结果。只有 `notFound`（HTTP 404）可以触发"本地作为新文件上传"的同步路径；`error` 必须中止该文件的同步（feature-matrix §D5）。

### `RemoteFile` 类 <a id="remotefile-class"></a>

- **来源：** `lib/src/webdav/webdav_client.dart`。
- **用途：** `WebDavClient.download()` 的判别式结果。区分"远程不存在文件"（404）与传输/服务器失败，使错误不可能覆盖远程数据（feature-matrix §D5–D6）。
- **字段：** `status`（`RemoteFileStatus`）、`content`（`String?`）、`etag`（`String?`）、`error`（`String?`）。
- **构造函数：**
  - `RemoteFile.found(String content, {String? etag})` — 200 响应，带正文和 ETag。
  - `RemoteFile.notFound()` — HTTP 404。
  - `RemoteFile.failure(String error)` — 任何非 404 的失败。

### `WebDavClient` 类 <a id="webdavclient-class"></a>

- **来源：** `lib/src/webdav/webdav_client.dart`。
- **用途：** 纯 WebDAV 传输客户端。内部基于实例；应用门面通过委托给一个惰性构建的 `WebDavClient` 单例来保留它们的静态 API。不执行任何本地文件系统 I/O。
- **构造函数：** `WebDavClient(WebDAVConfig config, {http.Client? httpClient, Duration lockTtl = 60s, Duration heartbeatInterval = 20s, Duration propfindTimeout = 15s, Duration retryDelay = 1s})`。当 `httpClient` 为 null 时，每次调用都新建一个 `http.Client()`（与应用 §A8 一致）；提供了时，生命周期由调用方拥有。
- **URL/认证辅助：**
  - `remoteFileUrl(String fileName)` — 构建完整远程 URL（去掉 `serverUrl` 尾部 `/`，确保 `remotePath` 以 `/` 结尾，不做 URL 编码；§A5）。
  - `authHeaders()` — HTTP Basic 认证 `Authorization` 头（§A6）。
  - `static strongEtag(String? etag)` — 仅在强 ETag 时返回（过滤 `W/` 和 null）。
  - `lockTtlSeconds` getter — 秒为单位的 TTL（由 `lockTtl` 派生）。
  - `lockFileName` 常量 — `.lock`（§B1）。
- **重试：** `withRetry<T>(attempt, {shouldRetry, retries = 2})` — I3 策略：对 `SocketException`/`TimeoutException`/`http.ClientException`/`HttpException` 以及 `shouldRetry`（5xx）重试；4xx 绝不重试；退避 = `retryDelay * attemptIndex`（§D1–D4）。
- **动词：**
  - `testConnection()` — PROPFIND Depth:0，10 秒超时，对 207 或 404 返回 `true`（§A9–A10）。
  - `ensureRemoteDir()` — 在基础路径上 MKCOL，10 秒超时，吞掉所有错误（§A11）。
  - `ensureRemoteSubDir(String name)` — 在子目录上 MKCOL（§A12）。
  - `download(String name)` — GET，30 秒超时，5xx 重试，返回 `RemoteFile`（§A15/D5–D6）。
  - `upload(name, content, {ifMatchEtag, ifNoneMatchAll, retries = 2})` — PUT 字符串，30 秒超时，返回 `({is412, error})`，412 时带 `'conditional WebDAV PUT failed (HTTP 412)'`（§A13）。
  - `uploadBytes(name, bytes)` — PUT 二进制，120 秒超时，非 2xx 抛出（§A14）。
  - `downloadBytes(name)` — GET 二进制，120 秒超时，非 200 抛出（§A16）。
  - `delete(name, {etag})` — DELETE，10 秒超时，吞掉所有错误（§A17）。
  - `listSubDir(name)` — PROPFIND Depth:1，`propfindTimeout`，返回 `Set<String>?`（失败时 null；§C-P1–P4）。采用 MyDevice 的 `<(?:\w+:)?href>` 正则和 `p.basename`。
- **远程锁原语：**
  - `readRemoteUploadLock()` — 读取并解析 `.lock`；返回 `({lock, etag, error})`（§B）。
  - `writeRemoteUploadLock(lock, {ifMatchEtag, ifNoneMatchAll})` — 以 `retries: 0` 写入 `.lock`（§B10/D4）。
  - `deleteRemoteUploadLock({etag})` — 删除 `.lock`（§A17/B）。
- **心跳：** `withLockHeartbeat({refreshLock, operation})` — 运行 `operation`，同时以 `heartbeatInterval` 周期调用 `refreshLock`；心跳错误被吞掉（§B6）。`refreshLock` 闭包由同步引擎（P2.6）提供。
- **备注：** 该类**不执行任何本地文件系统 I/O**。本地锁文件管理、客户端 ID 持久化和基线快照存储属于同步引擎（P2.6），它用 `StorageAdapter` 组合这些远程原语。
