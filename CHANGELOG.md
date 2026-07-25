# Changelog

## 1.0.0 - 2026-07-25

First stable release. No engine code changed since `0.9.0` — this tag marks the surface as **proven
by integration**: all three apps (MyAnime, MyDay, MyDevice) now consume the package, shipped on it in
their `v1.3.0` releases with green CI on all five platforms, and the old-build/new-build WebDAV
interop gate passed against a real server.

Integration outcome: ~7,700 lines of duplicated engine code removed across the three apps
(MyAnime 2,038 / MyDevice ~2,000 / MyDay 3,635), with every existing app test passing unmodified —
the facade approach held.

- `AGENTS.md` rewritten to contain only agent instructions. Everything describing what the code is or
  does now lives in `doc/en-us/`, with an explicit reading order (docs → comments → code) and a
  "docs are the primary artifact" maintenance rule.
- `doc/en-us/architecture.md` and `doc/en-us/README.md` updated for the completed state, including
  the per-app integration outcome and which app-specific behaviors deliberately stayed app-side.

## 0.9.0 - 2026-07-24

Pre-integration release: the complete shared engine surface (PLAN.md Phase 2,
tasks P2.1-P2.10). No app consumes it yet; Phase 3 wires the submodule and the
per-app facades.

- Added the P2.10 package golden suite: 36 package-owned fixtures replay the
  ten P0.2 WebDAV scenarios plus backup-v2 bundle and ZIP-export formats for
  synthetic MyAnime (1 module), MyDay (5 modules), and MyDevice (4 modules)
  registries. Deterministic client IDs, clocks, lock timing, fake WebDAV state,
  record/verify mode, app file order, remote paths, image-reference placement,
  backup keys, and archive prefixes make the fixtures suitable for CI.
- CI's unfiltered `flutter test` step is explicitly named as the unit-and-golden
  gate. The package fixtures preserve P0.2 request topology while recording the
  shared engine's intentional conflict-finalize remote re-download.

- Added `AutoSyncScheduler`, `AutoSyncResult`, and the `AutoSyncPredicate`/
  `AutoSyncRunSync`/`AutoSyncConsumeLocalDataChanged`/`AutoSyncSideEffect` hooks
  under `lib/src/sync/` (feature-matrix §H): `WidgetsBindingObserver` lifecycle
  (resume-only), 30s trailing-edge save debounce, 15min periodic timer,
  `requestSyncNow`, the `_syncing` silent-skip guard, in-memory status
  (`lastSuccessAt`/`lastFailureAt`/`lastError`/`hasPendingConflicts`), reload
  and status listener fan-out, and `recordSyncResult`/`recordFinalizeResult`.
  App-specific differences survive as hooks: `onPeriodicTick` (MyAnime/MyDevice
  daily backup; MyDay null per H5) and `onResume` (H6 side-effect bundles).
  Launch/periodic/resume are unified on canceling a pending debounce before
  syncing immediately (MyAnime's behavior).
- Added `fake_async` as a dev dependency for timer-based scheduler tests.

- Added `ZipTransfer`, `ZipClock`, and `ZipAfterImportHook` under
  `lib/src/data/` (feature-matrix §M): registry-driven export of module data
  files plus flat `images/<basename>` entries (never config/`.sync_base/`/
  `backups/`), per-app `archiveNamePrefix` (`myanime_export_`, `myday_backup_`,
  `mydevice_export_`), fixed `yyyyMMdd_HHmmss` naming and `flush: true`, and a
  two-phase import standardized on MyDay's strict semantics (`p.url.normalize`
  + traversal rejection, containment check). Per-app leniency is preserved via
  knobs `rejectUnknownEntries` (M7), `strictUtf8` (M8), `validateBeforeWrite`
  and `atomicWrites` (M9, validator = `DataModule.validate`), plus the optional
  `onAfterImport` hook (M10).
- Added focused P2.8 tests covering export entry lists/prefixes/skips,
  round-trip import, overwrite semantics, traversal/unknown/nested-entry
  rejection vs lenient skipping, strict vs tolerant UTF-8,
  validation-before-write atomicity, plain write mode, decoder leniency, and
  the after-import hook.

- Added `BackupEngine`, `BackupInfo`, `RestoreResult`, and `BackupClock` under
  `lib/src/backup/` (feature-matrix §J): v2 bundle creation (`_backupFormat` +
  per-module raw JSON strings + `_imageRefs`; no `createdAt`/`modules`), sha256
  content-addressed blob store with exists-check dedup, reference-counted GC
  (10-minute grace, abort-on-unparseable), age-based retention (0 = forever),
  corrupt-bundle flagging with 4 MiB probe cap, re-entrancy-guarded daily
  auto-backup with corrupt-doesn't-count retry, and validate-before-write
  v1/v2 restore returning `RestoreResult{ok, wroteAnything, missingImages}`.
- Restore implements the I5 safety rule inside the engine: when the persisted
  WebDAV config is configured with `autoSync: true` it is disabled before the
  first file write and re-enabled only when the restore failed without writing
  anything. Per-app differences are constructor knobs: `syntheticImagesModule`
  (J3, MyDevice), `blobGcGrace` (J9), and `probeMaxBytes` (J12); image-key
  sanitization is standardized on MyDevice's tolerant basename form (J17).
- Added `DataFileValidationException` to `lib/src/modules/data_module.dart`
  (feature-matrix §K8) as the shared typed validation failure for
  `DataModule.validate` callbacks.
- Added focused P2.7 tests covering bundle shape, blob dedup/GC/grace,
  retention, listing/probing, module selection, v1/v2 restore, sanitizer
  rejection, synthetic images gating, I5 toggle outcomes, auto-backup cadence,
  and settings persistence.

- Added `StorageAdapter`, `DataModule`, `ModuleRegistry`, app-neutral conflict/
  pending contracts, and `WebDavSyncEngine`. The engine implements config/base/
  client-ID persistence, interrupted upload recovery, remote lock acquire/
  refresh/heartbeat/release, ordered raw fast paths and module merges, one-time
  concurrent local re-read, conflict finalization, sticky local-change signals,
  additive referenced-image sync, and force upload/download.
- Expanded the fake WebDAV server to retain MKCOL-created empty collections and
  added focused P2.6 tests for file-state branches, transforms and real schema
  preservation, lock takeover/resume/412, base timing, pending/finalize,
  image-order/listing behavior, force operations, progress, and operation guard.
- Added `WebDavClient`, `WebDAVConfig`, `WebDAVUploadLock`, `UploadSession`,
  `RemoteFile`, and `RemoteFileStatus` under `lib/src/webdav/`: pure WebDAV
  transport (PROPFIND/MKCOL/GET/PUT/DELETE verbs, HTTP Basic auth, URL
  normalization), I3 retry policy (2 extra attempts, 1s/2s backoff, 5xx-only),
  remote upload-lock primitives (read/write/delete `.lock` with `If-Match`/
  `If-None-Match` preconditions and `retries: 0`), lock-heartbeat mechanism,
  and the discriminated `RemoteFile` download result (found/notFound/error).
  All TTL/heartbeat/timeout/backoff knobs are injectable with fixed defaults.
- Added `atomicWriteString`, `atomicWriteBytes`, and `AtomicWriteQueue` under
  `lib/src/storage/`: same-directory tmp-then-rename replacement, `flush: true`,
  best-effort temp cleanup, destination-aware `FileSystemException`, and
  failure-resilient per-owner write serialization.
- Added the generic JSON unknown-field preservation engines under
  `lib/src/json/`: the schema-driven `JsonPreservation` (MyDay style) and the
  flat-map `unknownJsonFields`/`mergeUnknownJsonFields`/`jsonValueEquals`
  helpers (MyDevice style).
- Added the generic three-way record merge engine under `lib/src/merge/`:
  `mergeRecords<T>`, `RecordConflict<T>`, `RecordMergeResult<T>` (MyDevice
  superset signature with optional `mergeUnknownFields`).
- Exported both P2.2/P2.3 APIs from `lib/myapps_data.dart` and added focused
  unit tests (deletion matrix, identical-content suppression, autoResolve,
  schema round-trips, flat-map three-way merge).
- Added the byte-identical shared `SyncPhase`, `SyncProgress`, and
  `SyncProgressListenable` API under `lib/src/webdav/`.
- Added the byte-identical, reference-counted `SyncWakeLock` helper under
  `lib/src/sync/`, including ownership-safe wake-lock behavior.
- Exported both P2.1 APIs from `lib/myapps_data.dart` and added focused unit tests.
- Package scaffold: pubspec, lint config, CI (analyze + test), AGENTS.md/README,
  GPL-3.0 license, and smoke test.
