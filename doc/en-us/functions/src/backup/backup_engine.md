# lib/src/backup/backup_engine.dart

Generic local backup engine (P2.7), reconciled from the three apps' `backup_service.dart`
implementations (feature-matrix §J). Backup format v2 bundles store per-module raw JSON strings
plus an `_imageRefs` map pointing at a content-addressed `backups/blobs/<sha256><ext>` store with
reference-counted GC; legacy v1 bundles with inline base64 `_images` remain restorable.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `BackupClock` | typedef | A | Supply the current local time; injectable for tests. |
| `RestoreResult` | class | A | Report restore success, write flag, and missing-image count. |
| `RestoreResult` | constructor | A | Create an immutable restore result. |
| `BackupInfo` | class | A | Describe one listed backup bundle. |
| `BackupInfo` | constructor | A | Create an immutable backup info entry. |
| `BackupInfo.displaySize` | getter | A | Format B/KB/MB identical to the apps. |
| `BackupEngine` | class | A | Create/list/restore/delete backups plus daily auto-backup. |
| `BackupEngine` | constructor | A | Bind storage, registry, and J-knobs. |
| `BackupEngine.loadSettings` | method | A | Read `autoBackupEnabled`/`backupRetentionDays` from config. |
| `BackupEngine.saveSettings` | method | A | Persist both keys, preserving unrelated config keys. |
| `BackupEngine._getBackupDir` | private method | A | Resolve/create `backups/`. |
| `BackupEngine._getBlobDir` | private method | A | Resolve/create `backups/blobs/`. |
| `BackupEngine._formatStamp` | private static method | A | Format `yyyyMMdd_HHmmss` without `intl`. |
| `BackupEngine._parseStamp` | private static method | A | Strictly parse the filename stamp. |
| `BackupEngine.createBackup` | method | A | Write a v2 bundle atomically, then retention + blob GC. |
| `BackupEngine.runAutoBackupIfNeeded` | method | A | Guarded once-per-day auto-backup. |
| `BackupEngine.listBackups` | method | A | List newest-first with corrupt flags and blob sizes. |
| `BackupEngine.getBackupModules` | method | A | Report module ids present in a bundle. |
| `BackupEngine._safeImageBasename` | private static method | A | Tolerant flat image-key sanitization (J17). |
| `BackupEngine._loadWebDavConfig` | private method | A | Load `webdav_config.json` for the I5 interplay. |
| `BackupEngine._saveWebDavConfig` | private method | A | Persist `webdav_config.json` atomically. |
| `BackupEngine._enableAutoSyncAfterUntouchedRestore` | private method | A | Best-effort auto-sync re-enable. |
| `BackupEngine.restoreBackup` | method | A | Validate-then-write restore with I5 auto-sync toggle. |
| `BackupEngine.deleteBackup` | method | A | Delete a bundle, then garbage collect blobs. |
| `BackupEngine._cleanOldBackups` | private method | A | Age-based retention (0 = forever). |
| `BackupEngine._collectUnreferencedBlobs` | private method | A | Conservative reference-counted blob GC. |

## Bundle format (fixed, I2/C8)

`createBackup` writes `backups/backup_<yyyyMMdd_HHmmss>.json` containing exactly
`{'_backupFormat': 2}`, one key per existing module file holding its raw JSON text as a string
(registry order), and `_imageRefs` (`'images/<name>' -> '<sha256><ext>'`) only when images exist.
There is no `createdAt` and no `modules` field (correction C8). `_images` is legacy v1 read-only.

## Blob store and GC

Images are sha256-content-addressed under `backups/blobs/`; identical bytes across any number of
backups share one physical blob (write skipped when it already exists). GC runs after every create
and delete, is reference-counted across every remaining bundle, aborts the whole pass when any
bundle is unparseable (J10), and never deletes blobs younger than `blobGcGrace` (default 10
minutes, J9) so a concurrent `createBackup` is never raced.

## Restore

`restoreBackup` validates every selected module payload through `DataModule.validate` before the
first write (K8), writes atomically via P2.4 helpers, and restores images from v2 blob references
or legacy v1 inline base64. Missing blobs increment `missingImages` without failing the restore.
Image keys are sanitized with MyDevice's tolerant `_safeImageBasename` (J17): bare basenames and
`images/<name>` keys are accepted; traversal, nesting, and absolute paths are rejected.

With `syntheticImagesModule` (J3; MyDevice only), `getBackupModules` appends an `images` module id
when a bundle carries either image format, and image restoration is gated on that module being
selected. Otherwise images always restore.

## I5 auto-sync interplay

When `webdav_config.json` exists, is configured, and has `autoSync: true`, `restoreBackup`
disables auto-sync BEFORE the first file write. If the restore then fails with
`wroteAnything == false` (local data provably untouched), auto-sync is re-enabled best-effort; in
every other outcome it stays off. The post-restore force-upload offer remains app-side UI.

## Auto-backup

`runAutoBackupIfNeeded` is re-entrancy guarded, reloads settings each call, and creates at most
one backup per calendar day. The "already backed up today" check scans bundle filenames and
ignores corrupt bundles, so an interrupted write is retried (J14/J15). No `lastBackupAt` key is
persisted (L3). The host owns the trigger cadence (J21/H5): MyAnime/MyDevice call it from their
auto-sync timer; MyDay calls it from its `ReminderService` 30-second loop.
