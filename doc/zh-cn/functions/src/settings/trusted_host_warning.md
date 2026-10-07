# lib/src/settings/trusted_host_warning.dart

## 声明

| 声明 | 职责 |
|---|---|
| `MyAppsTrustedHostWarningLabels` constructor | 标题、包含主机名的正文、确认复选框文案和操作按钮文案 |
| `showMyAppsTrustedHostWarning` | 模态风险警告，仅在勾选确认并点击确认后返回 true |
| `_TrustedHostWarning` constructor/createState | 针对一个主机的对话框组件 |
| `_TrustedHostWarningState` build | 正文、确认复选框、取消按钮和错误色确认按钮 |

共八个声明（三个类、两个构造器、一个 createState、一个 build 方法和一个函数）。策略已允许的端点
（HTTPS、私有网络、Tailscale `*.ts.net`、EasyTier `*.et.net`）无需此警告；它只用于让密钥发往
公网明文 HTTP 主机的显式例外。未勾选复选框时确认按钮不可用；取消或关闭返回 false。调用方先用
`normalizeTrustedHostEntry` 校验输入，仅在返回 true 时将其加入设备本地受信任列表。
