# lib/src/webdav/upload_lock.dart

WebDAV 上传锁值类型和会话句柄。上传锁子系统在三个应用间逐字节相同（feature-matrix §B1–B11）。本文件只保存值类型和会话句柄；本地锁文件持久化和客户端 ID 管理留在同步引擎里（P2.6）。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| [`defaultLockTtlSeconds`](#defaultlockttlseconds-constant) | 常量 | A | 默认锁 TTL（60 秒，feature-matrix §B5）。 |
| [`WebDAVUploadLock`](#webdavuploadlock-class) | 类 | A | 远程 `.lock` 值类型，带 JSON 往返、过期检查、会话匹配和心跳刷新。 |
| [`UploadSession`](#uploadsession-class) | 类 | A | 持有远程 `.lock` 的上传会话句柄。 |

## 文档

### `defaultLockTtlSeconds` 常量 <a id="defaultlockttlseconds-constant"></a>

- **来源：** `lib/src/webdav/upload_lock.dart`。
- **值：** `60`（feature-matrix §B5，I3）。
- **用途：** 当 `ttlSeconds` 缺失时，`WebDAVUploadLock.fromJson` 使用的默认 TTL（秒）。

### `WebDAVUploadLock` 类 <a id="webdavuploadlock-class"></a>

- **来源：** `lib/src/webdav/upload_lock.dart`。
- **用途：** 表示存储在远程 `.lock` 文件中的 WebDAV 上传锁。模式：`{clientId, token, startedAt, updatedAt, ttlSeconds}`，时间为 UTC ISO8601（feature-matrix §B4）。
- **字段：**
  - `clientId`（`String`）— 稳定的本地客户端标识符（UUID v4）。
  - `token`（`String`）— 每次上传的令牌（UUID v4，除恢复外每次会话重新生成）。
  - `startedAt`（`DateTime`）— 本锁首次被获取的时间（UTC）。
  - `updatedAt`（`DateTime`）— 最近一次心跳刷新的时间（UTC）。
  - `ttlSeconds`（`int`）— 锁的存活时间（秒）。
- **构造函数：**
  - `WebDAVUploadLock({required clientId, required token, required startedAt, required updatedAt, required ttlSeconds})`。
  - `WebDAVUploadLock.fromJson(Map<String, dynamic>)` — 从远程 `.lock` JSON 解析；`ttlSeconds` 缺失时默认为 `defaultLockTtlSeconds`（60）。
- **方法：**
  - `toJson()` — 以 UTC ISO8601 时间戳序列化为 `.lock` JSON 格式。
  - `isExpired(DateTime now)` — 当 `now - updatedAt >= ttlSeconds` 时为 `true`（§B11）。
  - `matches(String clientId, String token)` — 两个字段都匹配时为 `true`（§B7）。
  - `refreshed(DateTime updatedAt)` — 返回带新 `updatedAt` 的副本（保留 `clientId`、`token`、`startedAt`、`ttlSeconds`）。
  - `toString()` — 编码为 JSON 字符串（`WebDavClient.writeRemoteUploadLock` 的便捷方法）。

### `UploadSession` 类 <a id="uploadsession-class"></a>

- **来源：** `lib/src/webdav/upload_lock.dart`。
- **用途：** 持有远程 `.lock` 的上传会话句柄。在应用中这是私有 `_UploadSession`；在这里公开，以便同步引擎（P2.6）能在 `WebDavClient` 上的锁管理调用之间传递它。
- **字段：** `clientId`（`String`）、`token`（`String`）。
- **构造函数：** `UploadSession({required clientId, required token})`。
- **备注：** 值类型；相等性即同一性（与应用中的用法一致）。
