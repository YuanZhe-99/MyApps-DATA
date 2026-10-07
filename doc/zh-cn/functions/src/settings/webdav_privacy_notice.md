# lib/src/settings/webdav_privacy_notice.dart

## 声明

| 声明 | 职责 |
|---|---|
| `MyAppsWebDavPrivacyItem` constructor | 一个数据模块或可选内容条目：标题和可选说明 |
| `MyAppsWebDavPrivacyNoticeLabels` constructor | 所有本地化文案，包括判定描述函数和不安全 HTTP 警告 |
| `MyAppsWebDavPrivacyNotice` constructor/build | 提醒正文：简介、上传的数据模块、可选内容、目标主机、可选的“不发往第三方”声明、服务器端加密说明、传输安全状态 |
| `showMyAppsWebDavPrivacyNotice` | 模态对话框，确认时返回 true，拒绝或关闭时返回 false |
| `MyAppsWebDavSyncPausedBanner` constructor/build | 同步已暂停的提示和查看操作 |

共十一个声明（四个类及其构造器、两个 build 方法和一个函数）。应用从自己的注册表提供数据清单，并提供目标主机、加密说明以及 `evaluateEndpointSecurity` 给出的 `EndpointVerdict`。发往公网主机的明文 HTTP（`insecureHttp`）会额外显示错误色警告；未受保护的判定显示打开的锁。只有对话框返回 true 时，调用方才保存确认记录并启用同步；返回 false 时不存储任何内容，也不发出请求。组件不执行网络或存储操作。
