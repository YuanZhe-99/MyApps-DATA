# lib/myapps_data.dart

这是包的公共桶文件。P2.1–P2.10 导出同步进度、前台唤醒锁、JSON 保留、泛型合并、原子 I/O、WebDAV 客户端、模块注册表、存储适配器、同步引擎、备份引擎、ZIP 传输和自动同步调度器 API（见 [../architecture.md](../architecture.md)）。P2.10 在不新增公共 API 的情况下补全了包测试门槛。公共类型从这里再导出；使用者绝不能直接导入 `package:myapps_data/src/...` 路径，只能导入 `package:myapps_data/myapps_data.dart`。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| [`library` 指令](#library-directive) | 库声明 | A | 声明包的公共桶文件，并记录其规划的导出面。 |

## 文档

### `library;` <a id="library-directive"></a>
- **种类：** 库指令（文件级声明，不是函数）。
- **来源：** `lib/myapps_data.dart`（第 12 行）。
- **用途：** 把本文件命名为 `myapps_data` 包的公共桶文件——每个使用者（MyAnime、MyDay、MyDevice）导入共享功能的唯一入口。
- **输入：** 无；它是库声明，不可调用。
- **返回：** 不适用。
- **副作用：** 无。
- **算法：** 不适用——没有运行时行为。该声明纯粹用于命名和记录这个库，并作为导出语句的目标。
- **用法：** 消费代码导入 `package:myapps_data/myapps_data.dart`，以访问当前进度/唤醒锁、保留、合并、原子 I/O、WebDAV 客户端、模块、存储、同步引擎、备份引擎、ZIP 传输和自动同步调度器 API。
- **备注：** 附带的文档注释列出了每个引擎区域落地后的规划导出面：`storage/`（`StorageAdapter`、原子 I/O）、`json/`（保留引擎）、`merge/`（`mergeRecords<T>`）、`modules/`（`DataModule`、`ModuleRegistry`）、`webdav/`（配置、客户端、上传锁、同步引擎、进度）、`sync/`（自动同步调度器、唤醒锁）、`backup/`（`BackupEngine`）和 `data/`（ZIP 传输）。P2.1–P2.10 已提供进度、唤醒锁、保留、合并、原子 I/O、WebDAV 客户端、模块/存储契约、同步引擎、备份引擎、ZIP 传输和自动同步调度器导出；此页面必须与包的 golden 覆盖保持一致；此页面必须随后续新增导出保持同步。
