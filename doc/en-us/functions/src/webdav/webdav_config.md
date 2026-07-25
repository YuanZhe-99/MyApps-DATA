# lib/src/webdav/webdav_config.dart

Persisted WebDAV configuration shared by MyAnime / MyDay / MyDevice. Behavior-identical to the
three apps' `WebDAVConfig` (feature-matrix §A1-A4) except that `remotePath` defaults to `''`
instead of a per-app constant; the per-app default is injected by the sync engine or app facade.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| [`WebDAVConfig`](#webdavconfig-class) | class | A | Persisted WebDAV server/path/credentials/autoSync value type with JSON round-trip. |

## Documentation

### `WebDAVConfig` class <a id="webdavconfig-class"></a>

- **Source:** `lib/src/webdav/webdav_config.dart`.
- **Purpose:** Holds the five WebDAV configuration fields (`serverUrl`, `username`, `password`,
  `remotePath`, `autoSync`) and provides JSON serialization, a `.nextcloud()` factory, and a
  `copyWith` that updates only `autoSync`.
- **Fields:**
  - `serverUrl` (`String`) - WebDAV server base URL.
  - `username` (`String`) - HTTP Basic auth username.
  - `password` (`String`) - HTTP Basic auth password.
  - `remotePath` (`String`, default `''`) - Remote collection path. The per-app default
    (`/MyAnime`, `/MyDay`, `/MyDevice`) is applied by the engine/facade.
  - `autoSync` (`bool`, default `false`) - Whether auto-sync is enabled.
- **Constructors:**
  - `WebDAVConfig({required serverUrl, required username, required password, remotePath = '', autoSync = false})`.
  - `WebDAVConfig.fromJson(Map<String, dynamic>)` - deserializes from `webdav_config.json`;
    missing fields default to `''`/`false`.
  - `WebDAVConfig.nextcloud(String host, String username, String password)` - constructs
    `serverUrl = 'https://$host/remote.php/dav/files/$username'`.
- **Getters:** `isConfigured` - `true` when `serverUrl`, `username`, and `password` are all
  non-empty (does not check `remotePath`).
- **Methods:** `copyWith({bool? autoSync})` - returns a copy with only `autoSync` replaced;
  `toJson()` - serializes all five fields to a JSON-compatible map.
- **Notes:** feature-matrix §A1-A4. The `remotePath` default differs from the apps (which use
  per-app constants) because the package has no app-specific knowledge. The `WebDavSyncEngine`
  (P2.6) applies the per-app `defaultRemotePath` when loading config.
