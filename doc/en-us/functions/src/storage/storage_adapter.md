# lib/src/storage/storage_adapter.dart

App-supplied storage boundary for all shared engines. The package never imports AnimeStorage,
TodoStorage, or DeviceStorage directly.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `StorageAdapter` | abstract class | A | Expose the active app directory and app storage-config persistence. |
| `getAppDir` | abstract method | A | Resolve the active custom/default app data directory. |
| `readConfig` | abstract method | A | Read `storage_config.json` through the app storage hub. |
| `writeConfig` | abstract method | A | Persist `storage_config.json` while preserving app-owned keys. |

## Contract

`getAppDir()` is the only path source used by `WebDavSyncEngine`; data files, `images/`,
`webdav_config.json`, and `.sync_base/` are resolved beneath that directory. Each app adapter must
delegate to its existing storage hub so custom paths retain their current behavior.

`readConfig()` and `writeConfig()` refer to `storage_config.json`, not `webdav_config.json`.
P2.6 persists WebDAV configuration explicitly under the app directory. The config methods are part
of the shared adapter for later backup/storage engines.
