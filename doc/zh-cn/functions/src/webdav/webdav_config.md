# lib/src/webdav/webdav_config.dart

MyAnime / MyDay / MyDevice 共享的持久化 WebDAV 配置。与三个应用的 `WebDAVConfig`（feature-matrix §A1–A4）行为相同，唯一例外是 `remotePath` 默认为 `''` 而非按应用的常量；按应用的默认值由同步引擎或应用门面注入。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| [`WebDAVConfig`](#webdavconfig-class) | 类 | A | 持久化的 WebDAV 服务器/路径/凭据/autoSync 值类型，带 JSON 往返。 |

## 文档

### `WebDAVConfig` 类 <a id="webdavconfig-class"></a>

- **来源：** `lib/src/webdav/webdav_config.dart`。
- **用途：** 保存五个 WebDAV 配置字段（`serverUrl`、`username`、`password`、`remotePath`、`autoSync`），并提供 JSON 序列化、一个 `.nextcloud()` 工厂，以及一个只更新 `autoSync` 的 `copyWith`。
- **字段：**
  - `serverUrl`（`String`）— WebDAV 服务器基础 URL。
  - `username`（`String`）— HTTP Basic 认证用户名。
  - `password`（`String`）— HTTP Basic 认证密码。
  - `remotePath`（`String`，默认 `''`）— 远程集合路径。按应用的默认值（`/MyAnime`、`/MyDay`、`/MyDevice`）由引擎/门面应用。
  - `autoSync`（`bool`，默认 `false`）— 是否启用自动同步。
- **构造函数：**
  - `WebDAVConfig({required serverUrl, required username, required password, remotePath = '', autoSync = false})`。
  - `WebDAVConfig.fromJson(Map<String, dynamic>)` — 从 `webdav_config.json` 反序列化；缺失字段默认为 `''`/`false`。
  - `WebDAVConfig.nextcloud(String host, String username, String password)` — 构造 `serverUrl = 'https://$host/remote.php/dav/files/$username'`。
- **getter：** `isConfigured` — 当 `serverUrl`、`username` 和 `password` 全部非空时为 `true`（不检查 `remotePath`）。
- **方法：** `copyWith({bool? autoSync})` — 返回只替换 `autoSync` 的副本；`toJson()` — 把全部五个字段序列化为 JSON 兼容映射。
- **备注：** feature-matrix §A1–A4。`remotePath` 默认值与各应用不同（它们使用按应用常量），因为本包不包含应用特有知识。`WebDavSyncEngine`（P2.6）在加载配置时应用按应用的 `defaultRemotePath`。
