# lib/src/secrets/secret_store.dart

单个应用在其当前应用目录中的本地密钥文件。应用注入文件名和自己拥有的密钥命名空间。该文件从不在 `ModuleRegistry` 中，因此同步、备份和 ZIP 引擎从不读取它。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `SecretsUnreadableException` | 类 | A | 读取文件时的类型化 I/O 失败；继承 `FileSystemException`。 |
| `SecretsUnreadableException(...)` | 构造器 | A | 用消息、路径和 OS 错误创建异常。 |
| `SecretStore` | 类 | A | 按命名空间访问一个密钥文件。 |
| `SecretStore(...)` | 构造器 | A | 绑定存储、文件名、命名空间、`onSaved` 和时钟，并校验它们。 |
| `_lock` | 私有 getter | A | 同一文件名下所有 store 共用的应用内锁。 |
| `ownsId` | 方法 | A | id 为 `<namespace>:<rest>` 且命名空间已声明时为 true。 |
| `_checkId` | 私有方法 | A | 对不属于本应用的 id 抛出 `ArgumentError`。 |
| `file` | 方法 | A | 每次调用时在当前应用目录中定位文件。 |
| `load` | 方法 | A | 用于显示或请求的宽容读取；任何问题都返回空。 |
| `loadForWrite` | 方法 | A | 用于写入的严格读取；坏内容改名保留，I/O 错误抛出。 |
| `_setAside` | 私有方法 | A | 把坏内容改名为 `<fileName>.unreadable-<UTC timestamp>`。 |
| `withLock` | 方法 | A | 不交错地执行一次读-改-写。 |
| `save` | 方法 | A | 原子写入，然后调用 `onSaved`。 |
| `saveQuiet` | 方法 | A | 原子写入，不调用 `onSaved`。 |
| `keyFor` | 方法 | A | 本应用某个 id 的密钥，每次从磁盘读取。 |
| `setKey` | 方法 | A | 在锁内设置或清除（墓碑）本应用某个 id 的密钥。 |
| `configuredIds` | 方法 | A | 本应用持有可用密钥的 id。 |
| `deleteAll` | 方法 | A | 在锁内删除文件，不留墓碑。 |

共十八个声明。

## 命名空间

id 为 `ns:<rest>` 且 rest 非空时属于命名空间 `ns`。`keyFor` 和 `setKey` 拒绝其他命名空间的 id，`configuredIds` 不报告它们。命名空间限制的是 API，而不是文件：其他命名空间的条目在每次写入时都会保留，并照常参与交换。各应用应使用不同的文件名，使彼此的文件分开。

## 读取与失败处理

| 情况 | `load` | `loadForWrite` |
|---|---|---|
| 文件不存在或为空白 | 空 | 空 |
| 不是 UTF-8、不是 JSON 或不是 JSON 对象 | 空 | 改名保留，然后为空 |
| I/O 错误，或该路径不是文件 | 空 | `SecretsUnreadableException`，不作任何改动 |
| 坏内容改名失败 | — | `SecretsUnreadableException` |

保留文件的时间戳为去掉 `-`、`:` 和 `.` 的 UTC ISO-8601 时间，例如 `transcribe_secrets.json.unreadable-20261006T101500123456Z`，与 MyTranscribe 一致。

## 锁

`withLock` 在按文件名区分的 `AtomicWriteQueue` 上串行执行操作，进程内同一文件名的所有 `SecretStore` 实例共用该队列。锁不可重入：不要在操作内部调用 `withLock`、`setKey` 或 `deleteAll`，持锁期间也不要发起网络请求。
