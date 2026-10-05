# lib/src/settings/webdav_settings.dart

## 声明

| 声明 | 职责 |
|---|---|
| `MyAppsWebDavSettings` constructor/build | 四个连接字段、隐藏密码、端点变更回调和可选端点内容 |
| `MyAppsWebDavConnectionActions` constructor/build | 保存和测试操作，执行中状态来自外部 |
| `MyAppsWebDavSyncActions` constructor/build | 手动同步和强制操作，执行中状态来自外部 |
| `MyAppsWebDavAutoSync` constructor/build | 自动同步偏好 |
| `MyAppsWebDavDisconnect` constructor/build | 断开连接入口 |

共十五个声明（五个类、构造器和 build 方法）。应用负责控制器及其释放、文案、
默认远程路径、凭据、确认对话框、冲突解决、进度文案和持久化。组件不执行网络或
存储操作，操作只调用提供的回调。可选端点内容支持领域专用安全信息。
