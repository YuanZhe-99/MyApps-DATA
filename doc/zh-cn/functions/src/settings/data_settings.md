# lib/src/settings/data_settings.dart

## 声明

| 声明 | 职责 |
|---|---|
| `DataSettingsAction` | 标识同步、备份、导出、导入和存储操作 |
| `MyAppsDataSettingsTile` constructor/build | 呈现操作图标、标题、状态、选中态和导航提示 |
| `MyAppsBackupSettings` constructor/build | 呈现每日备份开关和全宽保留期下拉选择 |

应用提供本地化文案、值、路由和持久化回调。构建不调用引擎或写设置，用户操作
触发所提供的回调。恢复守卫、调度节奏和导入确认保持原样。Material 控件继承
应用主题。
