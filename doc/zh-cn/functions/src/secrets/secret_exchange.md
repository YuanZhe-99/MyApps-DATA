# lib/src/secrets/secret_exchange.dart

同步完成后，在同一服务器和同一远端目录上与 WebDAV 服务器交换单个应用的密钥文件，在同步引擎的 `.lock` 之外运行。两个方向都受安全端点策略限制。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `SecretExchangeMode` | 枚举 | A | `sync`、`forceUpload`、`forceDownload`。 |
| `SecretExchangeStatus` | 枚举 | A | `synced`、`skippedInsecure`、`nothingToDo`、`failed`。 |
| `SecretExchangeOutcome` | 类 | A | 状态、端点判定、方向标志、密钥数和错误。 |
| `SecretExchangeOutcome(...)` | 构造器 | A | 记录结果。 |
| `SecretExchangeOutcome.reason` | getter | A | 判定的 `EndpointReason`，任何状态下都存在。 |
| `SecretExchange` | 类 | A | 绑定 `SecretStore` 和客户端工厂的交换器。 |
| `SecretExchange(...)` | 构造器 | A | 绑定 store 和可选的 `WebDavClient` 工厂。 |
| `exchange` | 方法 | A | 按给定模式执行一次交换；从不抛出。 |
| `_sync` | 私有方法 | A | 下载、锁内合并与写入、条件上传，412 时重合并一次。 |
| `_forceUpload` | 私有方法 | A | 无条件上传本地副本。 |
| `_forceDownload` | 私有方法 | A | 用远端副本替换本地副本。 |
| `_synced` | 私有方法 | A | 构造成功结果。 |
| `_ownedKeyCount` | 私有方法 | A | 统计 store 命名空间内的可用密钥数。 |
| `_failed` | 私有方法 | A | 构造失败结果。 |
| `_parse` | 私有静态方法 | A | 解析下载内容；不存在为空，非对象为 null。 |
| `_same` | 私有静态方法 | A | 按编码字节比较两个文档。 |

共十六个声明。

## 同步模式

1. `evaluateEndpointUrl(config.serverUrl, trustedHosts: …)`。若被拒绝，返回带原因的 `skippedInsecure`，且**不发出任何请求**。
2. GET 文件并保留其 ETag。下载出错则交换失败。无法解析的远端文件视为不存在。
3. 在 store 锁内：`loadForWrite`，按键合并，有变化时静默写入。两侧都为空时返回 `nothingToDo`。
4. 合并结果与远端副本相同时，不上传直接返回。
5. 使用 `If-Match: <strong ETag>` PUT；文件不存在时使用 `If-None-Match: *`。
6. 收到 HTTP 412 时再次 GET。若失败，不上传直接失败。否则在锁内把磁盘上当前内容、上一次合并结果和新的远端副本合并并写入，再按新的标签条件 PUT 一次。第二次被拒绝则交换失败。

持锁期间不发起网络请求。本地 I/O 错误（`SecretsUnreadableException`）会在上传任何内容之前使交换失败。

## 强制模式

| 模式 | 请求 | 本地文件 | 说明 |
|---|---|---|---|
| `forceUpload` | 一次无条件 PUT | 只读 | 不 GET、不合并。本地文件为空时不上传（`nothingToDo`）。 |
| `forceDownload` | 一次 GET | 不同时替换 | 不 PUT、不合并。远端不存在时保留本地文件；远端无法解析时失败且不写入。 |

两者与 `sync` 一样受端点限制。

## 结果

`keyCount` 统计交换后 store 命名空间内的可用密钥数。`downloaded` 表示本地文件是否变化，`uploaded` 表示远端文件是否被写入。只有 `failed` 时才设置 `error`。面向用户的文案由应用负责。
