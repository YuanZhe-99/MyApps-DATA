/// Purpose: Public barrel for the `myapps_data` package — shared WebDAV sync and
/// data-management engines for MyAnime / MyDay / MyDevice.
/// Inputs: None (library declaration only).
/// Returns: N/A.
/// Side effects: None.
/// Notes: Engine areas, each documented under `doc/en-us/functions/src/`:
/// storage/ (StorageAdapter, atomic I/O), json/ (preservation engine), merge/
/// (mergeRecords&lt;T&gt;), modules/ (DataModule, ModuleRegistry), webdav/ (config,
/// client, upload lock, sync engine, progress), sync/ (auto-sync scheduler, wake
/// lock), backup/ (BackupEngine), data/ (ZIP transfer). Public API goes through
/// this barrel only; consumers must not import `src/` paths directly.
library;

// P2.1: verbatim moves from the three apps (byte-identical sources).
export 'src/webdav/sync_progress.dart';
export 'src/sync/sync_wake_lock.dart';
// P2.2: JSON unknown-field preservation engines (schema-driven + flat-map).
export 'src/json/json_preservation.dart';
// P2.3: generic three-way record merge engine.
export 'src/merge/sync_merge.dart';
// P2.4: generic atomic file replacement and optional serialized write queue.
export 'src/storage/atomic_io.dart';
// P2.5: WebDAV transport client, config, upload lock, and remote file result.
export 'src/webdav/webdav_config.dart';
export 'src/webdav/upload_lock.dart';
export 'src/webdav/webdav_client.dart';
// P2.6: app-neutral storage/module contracts and WebDAV sync orchestration.
export 'src/storage/storage_adapter.dart';
export 'src/modules/data_module.dart';
export 'src/webdav/sync_engine.dart';
// P2.7: local backup engine (v2 blob store, GC, retention, v1/v2 restore).
export 'src/backup/backup_engine.dart';
// P2.8: ZIP data transfer engine (registry allowlist, traversal rejection).
export 'src/data/zip_transfer.dart';
// P2.9: auto-sync scheduler (lifecycle/debounce/periodic core, app hooks).
export 'src/sync/auto_sync_scheduler.dart';
