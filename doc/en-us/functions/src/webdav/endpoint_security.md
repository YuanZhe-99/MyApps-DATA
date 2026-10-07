# lib/src/webdav/endpoint_security.dart

Pure, app-neutral secure-endpoint policy. It classifies how safely data can travel to a configured
endpoint and names the reason for every verdict, so a UI can explain *why*. The WebDAV privacy
notice uses it to show transport security; a secret channel exchanges data only when the verdict is
allowed, in both directions.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `EndpointSecurity` | enum | A | Transport class shown to users: `encrypted`, `privateNetwork`, `trustedHost`, `insecureHttp`, `unsupported`. |
| `EndpointReason` | enum | A | Named reason for a verdict. |
| `EndpointVerdict` | class | A | Immutable verdict: reason and the judged lowercased host. |
| `EndpointVerdict(...)` | constructor | A | Records a reason and host. |
| `EndpointVerdict.allowed` | getter | A | True for HTTPS, private-network HTTP and trusted-host HTTP. |
| `EndpointVerdict.security` | getter | A | Groups the reason into an `EndpointSecurity` class. |
| `evaluateEndpointUrl` | function | A | Judges an address given as text; blank or unparseable text is `deniedUnparseable`. |
| `evaluateEndpointSecurity` | function | A | Judges a parsed `Uri` against the rule table. |
| `_privateAddress` | private function | A | Recognises loopback, private, link-local, CGNAT and private IPv6 addresses. |
| `_privateIpv4` | private function | A | Recognises private IPv4 ranges. |
| `_privateName` | private function | A | Recognises names that only resolve privately. |
| `_isTrusted` | private function | A | Matches a host against the device's trusted hosts. |
| `normalizeTrustedHostEntry` | function | A | Validates and lowercases a typed trusted-host entry; URLs, ports and paths return null. |

Thirteen declarations.

## Rule table

| Address | Verdict | Reason |
|---|---|---|
| `https://` any host | allowed | `https` |
| `http://` `localhost`, `*.localhost`, `127.0.0.0/8`, `::1` | allowed | `loopback` |
| `http://` `10/8`, `172.16/12`, `192.168/16` | allowed | `privateIpv4` |
| `http://` `169.254/16` | allowed | `linkLocal` |
| `http://` `100.64/10` | allowed | `cgnat` |
| `http://` `fc00::/7`, `fe80::/10` | allowed | `privateIpv6` |
| `http://` `*.ts.net` | allowed | `tailnet` |
| `http://` `*.et.net` | allowed | `easytier` |
| `http://` `*.local` | allowed | `mdns` |
| `http://` host without a dot | allowed | `singleLabelHost` |
| `http://` trusted host, exact or `*.suffix` | allowed | `trustedHost` |
| `http://` anything else | refused | `deniedPublicHttp` |
| other schemes | refused | `deniedScheme` |
| blank, unparseable, or no host | refused | `deniedUnparseable` |

## Behavior

- The host is judged, never resolved; ports are ignored.
- An IPv4 address mapped into IPv6 (`::ffff:a.b.c.d`) is judged as the IPv4 address.
- Suffixes match on a label boundary: `evil.ts.net.example.com` is refused.
- Addresses are never treated as names, so a public IPv6 address does not pass the no-dot rule.
- Trusted entries are trimmed and case-insensitive; empty entries trust nothing. `*.example.com`
  covers `a.example.com` and not `example.com` or `notexample.com`.
- `security` maps `https` to `encrypted`, `trustedHost` to `trustedHost`, `deniedPublicHttp` to
  `insecureHttp`, `deniedScheme`/`deniedUnparseable` to `unsupported`, and every other reason to
  `privateNetwork`.

Changing what counts as secure changes a promise already made to users; change the tests first.
