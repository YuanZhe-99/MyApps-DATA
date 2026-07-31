# lib/src/storage/atomic_io.dart

泛型原子文件替换和可选的串行写入队列（P2.4），从 MyDay 的 `DataFileSafety`、三个备份服务、三个 WebDAV 服务，以及 MyDay 承载负载的逐存储写入队列调和而成。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `atomicWriteString` | 函数 | A | 用 UTF-8 文本原子替换一个文件。 |
| `atomicWriteBytes` | 函数 | A | 用字节原子替换一个文件。 |
| `_deleteTemporaryFile` | 私有函数 | A | 尽力而为地清理失败写入的临时文件。 |
| `AtomicWriteQueue` | 类 | A | 为一个存储所有者或文件串行化写入。 |
| `AtomicWriteQueue.enqueue` | 方法 | A | 追加一个操作，同时保留其自身的结果。 |
| `AtomicWriteQueue.idle` | getter | A | 观察当前队列尾部的完成。 |

## 原子替换

两个写入器使用同一序列：

1. 构建一个同目录临时路径，命名为 `<target>.tmp-<microsecondsSinceEpoch>`。
2. 需要时递归创建目标的父目录。
3. 用 `flush: true` 写入。
4. 把临时文件重命名覆盖目标。
5. 任何失败时，尽力而为地删除临时文件，并抛出 `FileSystemException`，其 `path` 指向预期目标。

不请求 fsync，因为目前没有任何源应用使用它。需要对同一目标并发写入的调用方应使用 `AtomicWriteQueue`。

## `AtomicWriteQueue`

该队列镜像 MyDay 的存储模式。每个存储所有者保留自己的实例，因此无关文件不会全局串行化。`enqueue` 按提交顺序恰好执行每个操作一次。失败的操作仍以该错误完成其面向调用方的 Future，同时内部队列尾部吸收失败，使后续写入继续。`idle` 等待在读取该 getter 之前已入队的操作。
