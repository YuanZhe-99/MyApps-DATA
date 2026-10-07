# lib/src/webdav/endpoint_security.dart

纯函数、与应用无关的安全端点策略。它判断数据发往已配置端点时的传输安全程度，并为每个判定给出具名原因，使界面能说明*为什么*。WebDAV 隐私提醒用它显示传输安全状态；密钥通道只在判定为允许时交换数据，两个方向同时受限。

## 声明

| 声明 | 种类 | Tier | 用途 |
|---|---|---|---|
| `EndpointSecurity` | 枚举 | A | 向用户显示的传输类别：`encrypted`、`privateNetwork`、`trustedHost`、`insecureHttp`、`unsupported`。 |
| `EndpointReason` | 枚举 | A | 判定的具名原因。 |
| `EndpointVerdict` | 类 | A | 不可变判定：原因和被判定的小写主机。 |
| `EndpointVerdict(...)` | 构造器 | A | 记录原因和主机。 |
| `EndpointVerdict.allowed` | getter | A | HTTPS、私有网络 HTTP 和受信任主机 HTTP 时为 true。 |
| `EndpointVerdict.security` | getter | A | 把原因归入 `EndpointSecurity` 类别。 |
| `evaluateEndpointUrl` | 函数 | A | 判定文本形式的地址；空白或无法解析的文本为 `deniedUnparseable`。 |
| `evaluateEndpointSecurity` | 函数 | A | 按规则表判定已解析的 `Uri`。 |
| `_privateAddress` | 私有函数 | A | 识别回环、私有、链路本地、CGNAT 和私有 IPv6 地址。 |
| `_privateIpv4` | 私有函数 | A | 识别私有 IPv4 网段。 |
| `_privateName` | 私有函数 | A | 识别只能在私有网络内解析的名称。 |
| `_isTrusted` | 私有函数 | A | 将主机与本设备的受信任主机列表匹配。 |
| `normalizeTrustedHostEntry` | 函数 | A | 校验并转小写用户输入的受信任主机条目；URL、端口和路径返回 null。 |

共十三个声明。

## 规则表

| 地址 | 判定 | 原因 |
|---|---|---|
| `https://` 任意主机 | 允许 | `https` |
| `http://` `localhost`、`*.localhost`、`127.0.0.0/8`、`::1` | 允许 | `loopback` |
| `http://` `10/8`、`172.16/12`、`192.168/16` | 允许 | `privateIpv4` |
| `http://` `169.254/16` | 允许 | `linkLocal` |
| `http://` `100.64/10` | 允许 | `cgnat` |
| `http://` `fc00::/7`、`fe80::/10` | 允许 | `privateIpv6` |
| `http://` `*.ts.net` | 允许 | `tailnet` |
| `http://` `*.et.net` | 允许 | `easytier` |
| `http://` `*.local` | 允许 | `mdns` |
| `http://` 不含点的主机 | 允许 | `singleLabelHost` |
| `http://` 受信任主机，精确匹配或 `*.suffix` | 允许 | `trustedHost` |
| `http://` 其他任何主机 | 拒绝 | `deniedPublicHttp` |
| 其他协议 | 拒绝 | `deniedScheme` |
| 空白、无法解析或没有主机 | 拒绝 | `deniedUnparseable` |

## 行为

- 只判断主机名本身，从不做 DNS 解析；端口被忽略。
- 映射到 IPv6 的 IPv4 地址（`::ffff:a.b.c.d`）按其 IPv4 地址判定。
- 后缀按标签边界匹配：`evil.ts.net.example.com` 被拒绝。
- 地址从不被当作名称，因此公网 IPv6 地址不会通过“不含点”规则。
- 受信任条目会去除首尾空白并忽略大小写；空条目不信任任何主机。`*.example.com` 覆盖 `a.example.com`，不覆盖 `example.com` 或 `notexample.com`。
- `security` 把 `https` 映射为 `encrypted`，`trustedHost` 映射为 `trustedHost`，`deniedPublicHttp` 映射为 `insecureHttp`，`deniedScheme`/`deniedUnparseable` 映射为 `unsupported`，其余原因映射为 `privateNetwork`。

改变“安全”的定义就是改变已对用户作出的承诺；先修改测试。
