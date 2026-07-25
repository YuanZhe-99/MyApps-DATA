# lib/myapps_data.dart

This is the package's public barrel file. P2.1-P2.10 export sync progress, foreground wake-lock,
JSON preservation, generic merge, atomic I/O, WebDAV client, module-registry, storage-adapter,
sync-engine, backup-engine, ZIP-transfer, and auto-sync-scheduler APIs (see
[../architecture.md](../architecture.md)). P2.10 completes the package test gate without adding a
new public API. Public types are re-exported from here; consumers must never import
`package:myapps_data/src/...` paths directly, only `package:myapps_data/myapps_data.dart`.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| [`library` directive](#library-directive) | library declaration | A | Declares the package's public barrel and documents its planned export surface. |

## Documentation

### `library;` <a id="library-directive"></a>
- **Kind:** library directive (file-level declaration, not a function).
- **Source:** `lib/myapps_data.dart` (line 12).
- **Purpose:** Names this file as the `myapps_data` package's public barrel — the single
  entry point through which every consumer (MyAnime, MyDay, MyDevice) imports shared
  functionality.
- **Inputs:** None; it is a library declaration, not a callable.
- **Returns:** N/A.
- **Side effects:** None.
- **Algorithm:** N/A - there is no runtime behavior. The declaration exists purely to name and
  document the library and to be the target of export statements.
- **Usage:** Consuming code imports `package:myapps_data/myapps_data.dart` to access current
  progress/wake-lock, preservation, merge, atomic-I/O, WebDAV client, module, storage, sync
  engine, backup engine, ZIP transfer, and auto-sync scheduler APIs.
- **Notes:** The accompanying doc comment lists the planned export surface once each engine
  area lands: `storage/` (`StorageAdapter`, atomic I/O), `json/` (preservation engine), `merge/`
  (`mergeRecords<T>`), `modules/` (`DataModule`, `ModuleRegistry`), `webdav/` (config, client,
  upload lock, sync engine, progress), `sync/` (auto-sync scheduler, wake lock), `backup/`
  (`BackupEngine`), and `data/` (ZIP transfer). P2.1-P2.10 have supplied progress, wake-lock,
  preservation, merge, atomic-I/O, WebDAV client, module/storage contracts, sync-engine,
  backup-engine, ZIP-transfer, and auto-sync-scheduler exports; this page must stay aligned as
  package golden coverage; this page must stay aligned as later exports are added.
