# MyApps-DATA 文档（简体中文）

这是 `myapps_data` 包的简体中文文档树——它提供通过模块和存储适配器接入的共享 WebDAV 同步与数据管理引擎。本目录镜像 `doc/en-us/`：相同的文件、标题、表格与示例，按照 [translation-guide.md](translation-guide.md) 中的术语表翻译。

**这些文档是代码的权威描述。** 仓库的 [AGENTS.md](../../AGENTS.md) 刻意只保留给代理的指令——工作流、编写规则、行为契约和发布流程——并在这里指向其余一切。代码变更时，这些页面先行更新；当文档与代码不一致时，以代码核实后修正页面。

## 目录

- [architecture.md](architecture.md) — 本包是什么、它的结构、每个引擎区域的现状，以及应用如何接入。
- [invariants.md](invariants.md) — 行为契约：硬不变量 I1–I10、统一规则，以及每一项已接受统一及其后果。**修改同步、备份或 ZIP 行为之前务必先读。**
- [feature-matrix.md](feature-matrix.md) — 共享行为和可配置策略。
- [translation-guide.md](translation-guide.md) — 共享基础设施的英译中翻译指南与术语表。
- [functions/INDEX.md](functions/INDEX.md) — 函数索引：`lib/` 中的每个声明，附指向完整逐文件文档的链接。


## 当前状态

完整并在生产中使用。所有引擎区域——存储、JSON 保留、合并、WebDAV 传输与同步、备份、ZIP 传输和自动同步调度——均已实现、从公共桶文件 `lib/myapps_data.dart` 导出，并在 `functions/` 下做了文档化。聚焦的单元测试加上 36 个包自有的 golden 固定件，在 CI 中覆盖共享行为和合成的单模块及多模块注册表形态。

应用可独立接入本包。选用的模块、适配器、领域策略和回归验证记录在各应用自身文档中。

每个新的源码区域必须在同一变更集中获得一个 `doc/en-us/functions/` 页面，以及相同相对路径的中文页面。
