# lib/src/webdav/webdav_client.dart

Pure WebDAV transport client - verbs, auth, retry, remote lock primitives, and heartbeat
mechanism. No local filesystem access. This is the P2.5 deliverable (feature-matrix §A-§D, §B,
§C). All timeouts, TTL, heartbeat, and retry backoff are injectable for tests with defaults fixed
to the apps' current values (I3).

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| [`RemoteFileStatus`](#remotefilestatus-enum) | enum | A | Outcome status of a download attempt (found/notFound/error). |
| [`RemoteFile`](#remotefile-class) | class | A | Discriminated download result distinguishing 404 from errors (§D5-D6). |
| [`WebDavClient`](#webdavclient-class) | class | A | Pure WebDAV transport: verbs, auth, retry, remote lock primitives, heartbeat. |

## Documentation

### `RemoteFileStatus` enum <a id="remotefilestatus-enum"></a>

- **Source:** `lib/src/webdav/webdav_client.dart`.
- **Values:** `found`, `notFound`, `error`.
- **Purpose:** Discriminates download outcomes. Only `notFound` (HTTP 404) may trigger the
  upload-local-as-new sync path; `error` must abort that file's sync (feature-matrix §D5).

### `RemoteFile` class <a id="remotefile-class"></a>

- **Source:** `lib/src/webdav/webdav_client.dart`.
- **Purpose:** Discriminated result of `WebDavClient.download()`. Distinguishes "file does not
  exist on remote" (404) from transport/server failures so errors cannot overwrite remote data
  (feature-matrix §D5-D6).
- **Fields:** `status` (`RemoteFileStatus`), `content` (`String?`), `etag` (`String?`),
  `error` (`String?`).
- **Constructors:**
  - `RemoteFile.found(String content, {String? etag})` - 200 response with body and ETag.
  - `RemoteFile.notFound()` - HTTP 404.
  - `RemoteFile.failure(String error)` - any non-404 failure.

### `WebDavClient` class <a id="webdavclient-class"></a>

- **Source:** `lib/src/webdav/webdav_client.dart`.
- **Purpose:** Pure WebDAV transport client. Instance-based internally; app facades keep their
  static APIs by delegating to a lazily-built `WebDavClient` singleton. Performs no
  local filesystem I/O.
- **Constructor:** `WebDavClient(WebDAVConfig config, {http.Client? httpClient, Duration lockTtl = 60s, Duration heartbeatInterval = 20s, Duration propfindTimeout = 15s, Duration retryDelay = 1s})`.
  When `httpClient` is null, each call creates a fresh `http.Client()` (matching apps' §A8);
  when provided, the caller owns the lifecycle.
- **URL/auth helpers:**
  - `remoteFileUrl(String fileName)` - builds the full remote URL (strips trailing `/` from
    `serverUrl`, ensures `remotePath` ends `/`, no URL-encoding; §A5).
  - `authHeaders()` - HTTP Basic auth `Authorization` header (§A6).
  - `static strongEtag(String? etag)` - returns the ETag only when strong (filters `W/` and null).
  - `lockTtlSeconds` getter - TTL in seconds (derived from `lockTtl`).
  - `lockFileName` constant - `.lock` (§B1).
- **Retry:** `withRetry<T>(attempt, {shouldRetry, retries = 2})` - I3 policy: retries on
  `SocketException`/`TimeoutException`/`http.ClientException`/`HttpException` and on
  `shouldRetry` (5xx); 4xx never retried; backoff = `retryDelay * attemptIndex` (§D1-D4).
- **Verbs:**
  - `testConnection()` - PROPFIND Depth:0, 10s timeout, returns `true` for 207 or 404 (§A9-A10).
  - `ensureRemoteDir()` - MKCOL on the base path, 10s timeout, swallows all errors (§A11).
  - `ensureRemoteSubDir(String name)` - MKCOL on a sub-directory (§A12).
  - `download(String name)` - GET, 30s timeout, retries on 5xx, returns `RemoteFile` (§A15/D5-D6).
  - `upload(name, content, {ifMatchEtag, ifNoneMatchAll, retries = 2})` - PUT string, 30s timeout,
    returns `({is412, error})` with `'conditional WebDAV PUT failed (HTTP 412)'` on 412 (§A13).
  - `uploadBytes(name, bytes)` - PUT binary, 120s timeout, throws on non-2xx (§A14).
  - `downloadBytes(name)` - GET binary, 120s timeout, throws on non-200 (§A16).
  - `delete(name, {etag})` - DELETE, 10s timeout, swallows all errors (§A17).
  - `listSubDir(name)` - PROPFIND Depth:1, `propfindTimeout`, returns `Set<String>?` (null on
    failure; §C-P1-P4). Adopts MyDevice's `<(?:\w+:)?href>` regex and `p.basename`.
- **Remote lock primitives:**
  - `readRemoteUploadLock()` - reads and parses `.lock`; returns `({lock, etag, error})` (§B).
  - `writeRemoteUploadLock(lock, {ifMatchEtag, ifNoneMatchAll})` - writes `.lock` with
    `retries: 0` (§B10/D4).
  - `deleteRemoteUploadLock({etag})` - deletes `.lock` (§A17/B).
- **Heartbeat:** `withLockHeartbeat({refreshLock, operation})` - runs `operation` while
  periodically calling `refreshLock` at `heartbeatInterval`; heartbeat errors are swallowed
  (§B6). The `refreshLock` closure is provided by the sync engine (P2.6).
- **Notes:** The class performs **no local filesystem I/O**. Local lock-file management,
  client-ID persistence, and base-snapshot storage belong to the sync engine (P2.6) which
  composes these remote primitives with `StorageAdapter`.
