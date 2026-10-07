# lib/src/secrets/secret_exchange.dart

Exchanges one application's secrets file with its WebDAV server after a sync, against the same
server and remote directory, outside the sync engine's `.lock`. Gated by the secure-endpoint policy
in both directions.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `SecretExchangeMode` | enum | A | `sync`, `forceUpload`, `forceDownload`. |
| `SecretExchangeStatus` | enum | A | `synced`, `skippedInsecure`, `nothingToDo`, `failed`. |
| `SecretExchangeOutcome` | class | A | Status, endpoint verdict, direction flags, key count and error. |
| `SecretExchangeOutcome(...)` | constructor | A | Records an outcome. |
| `SecretExchangeOutcome.reason` | getter | A | The verdict's `EndpointReason`, present for every status. |
| `SecretExchange` | class | A | Exchanger bound to a `SecretStore` and a client factory. |
| `SecretExchange(...)` | constructor | A | Binds the store and an optional `WebDavClient` factory. |
| `exchange` | method | A | Runs one exchange in the given mode; never throws. |
| `_sync` | private method | A | Download, locked merge and write, conditional upload, one re-merge on 412. |
| `_forceUpload` | private method | A | Unconditional upload of the local copy. |
| `_forceDownload` | private method | A | Replaces the local copy with the remote one. |
| `_synced` | private method | A | Builds a success outcome. |
| `_ownedKeyCount` | private method | A | Counts usable keys in the store's namespaces. |
| `_failed` | private method | A | Builds a failure outcome. |
| `_parse` | private static method | A | Parses a download; missing is empty, non-object is null. |
| `_same` | private static method | A | Compares documents by encoded bytes. |

Sixteen declarations.

## Sync mode

1. `evaluateEndpointUrl(config.serverUrl, trustedHosts: …)`. If refused, return `skippedInsecure`
   with the reason and make **no request**.
2. GET the file, keeping its ETag. A download error fails the exchange. A remote file that does not
   parse is treated as absent.
3. Under the store lock: `loadForWrite`, merge per key, write quietly if changed. If both sides are
   empty, return `nothingToDo`.
4. If the merge equals the remote copy, return without uploading.
5. PUT with `If-Match: <strong ETag>`, or `If-None-Match: *` when the file was absent.
6. On HTTP 412: GET again. If that fails, fail without uploading. Otherwise, under the lock, merge
   what is on disk now with the previous merge and the new remote copy, write, and PUT once more
   conditionally on the new tag. A second refusal fails the exchange.

No network call is made while the lock is held. A local I/O error
(`SecretsUnreadableException`) fails the exchange before anything is uploaded.

## Force modes

| Mode | Requests | Local file | Notes |
|---|---|---|---|
| `forceUpload` | one unconditional PUT | read only | No GET, no merge. An empty local file uploads nothing (`nothingToDo`). |
| `forceDownload` | one GET | replaced when different | No PUT, no merge. A missing remote keeps the local file; an unparseable one fails without writing. |

Both are gated exactly like `sync`.

## Outcome

`keyCount` counts usable keys in the store's namespaces after the exchange. `downloaded` reports
whether the local file changed, `uploaded` whether the remote file was written. `error` is set only
for `failed`. User-facing wording stays with the application.
