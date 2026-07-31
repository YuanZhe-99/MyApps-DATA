# lib/src/data/zip_transfer.dart

泛型 ZIP 数据传输引擎（P2.8），从三个应用的 `import_export_service.dart` 实现（feature-matrix §M）调和而成。导出恰好捆绑注册表的数据文件外加平铺的 `images/<basename>` 条目；导入以 MyDay 的严格语义为标准，按应用的宽容行为保留为构造函数开关。Markdown 导出留在应用侧（M14，非目标）。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `ZipClock` | 类型别名 | A | 提供当前本地时间；可为测试注入。 |
| `ZipAfterImportHook` | 类型别名 | A | 成功导入后的可选应用钩子（M10）。 |
| `ZipTransfer` | 类 | A | 注册表驱动的 ZIP 导出/导入。 |
| `ZipTransfer` | 构造函数 | A | 绑定存储、注册表、名前缀和 M 开关。 |
| `ZipTransfer._formatStamp` | 私有静态方法 | A | 不用 `intl` 格式化 `yyyyMMdd_HHmmss`（M2）。 |
| `ZipTransfer._isInside` | 私有静态方法 | A | 允许列表背后的包含检查（M6）。 |
| `ZipTransfer.exportZip` | 方法 | A | 写入一个带时间戳的数据文件与图像归档。 |
| `ZipTransfer.importZip` | 方法 | A | 对允许列表条目的两阶段校验导入。 |
| `ZipTransfer._writeBytes` | 私有方法 | A | 原子或普通条目写入（M9）。 |

## 导出

`exportZip(destDir)` 按注册表顺序添加每个既存注册表数据文件，然后添加 `images/` 中的每个文件为 `images/<basename>`（M3/M5），用 `package:archive` 默认设置编码（M13），并以 `flush: true` 写入 `<archiveNamePrefix><yyyyMMdd_HHmmss>.zip`（M1/M2/M11）。前缀开关保留 `myanime_export_`、`myday_backup_` 和 `mydevice_export_`。配置、`.sync_base/` 和 `backups/` 绝不打包（M4）。失败返回 null。

## 导入

`importZip(filePath)` 是两阶段的：每个条目在任何文件写入之前被分类（并在启用时被校验），因此被拒绝的归档绝不会留下部分写入。语义默认是 MyDay 的严格形式：

- 路径穿越（`p.url.normalize` 后的 `../`、`/../`）总是使导入失败（M6，固定）。
- 未知条目和格式错误的图像条目通过 `rejectUnknownEntries` 选择失败（true）或跳过（false）（M7；MyAnime/MyDevice 用 false）。
- 数据负载通过 `strictUtf8` 选择严格 UTF-8 解码（true）或原始写入（false）（M8）。
- `validateBeforeWrite` 在任何写入之前对每个数据条目运行 `DataModule.validate`（M9，true = MyDay）；`atomicWrites` 选择 tmp-重命名还是普通 `writeAsBytes`（M9）。
- 导入只在应用目录内覆盖，绝不触发重新同步或备份，并在成功后运行一次可选的 `onAfterImport` 钩子（M10）。不调用保留引擎（M15）；保留字段由应用校验器处理。
