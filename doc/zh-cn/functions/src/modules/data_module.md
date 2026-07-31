# lib/src/modules/data_module.dart

应用无关的模块描述符、合并结果、不透明冲突，以及取代每个硬编码按应用数据文件清单的有序注册表。

## 声明

本文件记录 22 个声明：六个回调类型别名、`DataFileValidationException`、`ModuleWriteReason`、`ModuleUploadContext`、`ModuleConflict`、`ModuleMergeOutcome`、`DataModule`、`ModuleRegistry`、它们的构造函数、`DataFileValidationException.toString` 和 `ModuleMergeOutcome.resolve`。

## `DataFileValidationException`

从 MyDay 的 `DataFileSafety`（feature-matrix §K8）抽取的类型化校验失败，携带 `fileName` 和 `message`。鼓励应用从 `validate` 回调抛出它，使备份恢复（P2.7）和 ZIP 导入（P2.8）失败能指名失败的模块文件；无论类型如何，任何被抛出的值都会中止写前校验。

## `DataModule`

每个描述符提供：

- `fileName`：持久化的本地/远程名称，如 `anime_data.json`；绝不重命名。
- `moduleId`：持久化的备份模块键；绝不重命名。
- `validate`：供面向校验的引擎使用的应用模型解析器。P2.6 刻意保留当前同步兼容性：直接远程副本是原始的，强制下载只做语法检查。
- `merge`：仅在本地和远程都存在且原始字符串不同时才调用的异步回调。缺失侧和原始相等分支绝不让负载经过应用模型规范化。
- `postMergeTransform`：可选异步变换，在无冲突合并和冲突解决之后运行。MyDay 财务用它在其实际的解决后位置上做强制余额迁移。
- `preUploadTransform`：带 base/本地/远程上下文的可选最终变换。MyDay 用它调用 `JsonPreservation`；模型级保留的应用把它留空。
- `referencedImages`：返回图像基名的可选应用解析器。
- `indexMergedUploadProgress`：合并上传是否报告模块索引/总数。默认为 true；MyDay 的结构化模块设为 false，以保留它们当前的不确定阶段。

回调返回最终字符串，不做包侧重新格式化。这保留了 MyDay 当前紧凑的生成 JSON，同时允许 MyAnime/MyDevice 模块回调返回美化 JSON。

## 合并结果

`ModuleMergeOutcome` 支持两种状态：

- 无冲突：需要 `mergedJson`。
- 待定：需要 `conflicts` 和 `buildResolvedJson`；`state` 可以保留应用类型化的合并结果，使 P3 门面能重建其既有的 `PendingSync` 字段。

`ModuleConflict` 存储不透明的本地/远程应用记录、显示名、既有记录 ID 和一个 `resolutionKey`。该键默认为 ID，但对于有多个可复用 ID 的记录容器的模块，可以加命名空间。

## `ModuleRegistry`

注册表冻结插入顺序，并提供按 `fileName` 和 `moduleId` 的查找映射。它拒绝空或重复的标识符。顺序在行为上意义重大：它控制 WebDAV 请求顺序、进度索引、部分写入顺序、冲突顺序、图像引用顺序和拼接错误顺序。
