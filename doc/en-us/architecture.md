# Architecture

## What this package is

`myapps_data` is the shared Flutter package holding the WebDAV sync engine and the data-management
engine (backup/restore, ZIP import/export, and the plumbing they share) for three sibling apps:
**MyAnime**, **MyDay**, and **MyDevice**.

Until the extraction, each app hand-maintained its own near-identical — and steadily drifting —
copies of:

```
lib/shared/services/webdav_service.dart
lib/shared/services/sync_merge.dart
lib/shared/services/sync_progress.dart
lib/shared/services/sync_wake_lock.dart
lib/shared/services/auto_sync_service.dart
lib/shared/services/backup_service.dart
lib/shared/services/import_export_service.dart
```

This package is now the single source of truth for that logic. Each app keeps its own data models,
UI, storage hub, and app-specific merge wrappers; everything shared arrives here. All three apps
shipped on it in their `v1.3.0` releases, and ~7,700 lines of duplicated engine code left them.

## Where the real plan lives

The authoritative extraction plan is `PLAN.md` at the workspace root (a sibling of the app
checkouts, not inside any git repository). It defines:

- The **hard invariants** (I1–I10) that any extraction must preserve — e.g. the WebDAV wire
  format, lock semantics (60-second TTL, 20-second heartbeat), the rule that restoring a backup
  disables auto-sync before the first write, and the rule that the real Gitea host is never
  committed anywhere.
- The **target package layout** under `lib/src/`: `storage/` (`StorageAdapter`, atomic I/O),
  `json/` (generic JSON-preservation engine), `merge/` (`mergeRecords<T>`), `modules/`
  (`DataModule`/`ModuleRegistry`), `webdav/` (config, client, upload lock, sync engine, progress),
  `sync/` (auto-sync scheduler, wake lock), `backup/` (backup engine), `data/` (ZIP transfer).
- The phased implementation tasks (drift audit, golden test harness, engine build-out, per-app
  integration via facades, and release).

Read `PLAN.md` before doing any structural work in this repository; this document only summarizes
what a reader of `doc/` needs to know without duplicating that plan.

## Current state (complete and in production)

Every engine area below is implemented, unit-tested, and consumed by all three apps. P2.1 moved two
files that were verified byte-identical across MyAnime, MyDay, and MyDevice:

- `lib/src/webdav/sync_progress.dart`: shared progress phases, immutable progress snapshots, and
  the `ValueListenable` type alias consumed by app UIs.
- `lib/src/sync/sync_wake_lock.dart`: the reference-counted, ownership-safe foreground sync wake
  lock. It never disables a lock owned by another feature and treats plugin failures as best-effort.

P2.2-P2.6 additionally provide:

- `lib/src/json/json_preservation.dart`: schema-driven and flat-map unknown-field preservation.
- `lib/src/merge/sync_merge.dart`: the generic three-way `mergeRecords<T>` engine.
- `lib/src/storage/atomic_io.dart`: same-directory tmp-then-rename string/byte writes and an
  optional failure-resilient serialized write queue.
- `lib/src/webdav/webdav_config.dart`: the shared `WebDAVConfig` (server URL, credentials, remote
  path, auto-sync flag, `.nextcloud()` factory, JSON round-trip).
- `lib/src/webdav/upload_lock.dart`: `WebDAVUploadLock` (the remote `.lock` value type with
  TTL/expiry/match/refresh) and `UploadSession` (the session handle).
- `lib/src/webdav/webdav_client.dart`: the pure `WebDavClient` transport — PROPFIND/MKCOL/GET/PUT/
  DELETE verbs, HTTP Basic auth, URL normalization, the I3 retry policy (2 extra attempts, 1s/2s
  backoff, 5xx-only), remote upload-lock primitives (read/write/delete with `If-Match`/
  `If-None-Match` and `retries: 0`), the lock-heartbeat mechanism, and the discriminated
  `RemoteFile`/`RemoteFileStatus` download result. All TTL/heartbeat/timeout/backoff knobs are
  injectable with fixed defaults.
- `lib/src/storage/storage_adapter.dart`: the app-supplied active storage-root/config boundary.
- `lib/src/modules/data_module.dart`: the ordered `ModuleRegistry`, app-owned merge/validation/
  preservation/image callbacks, opaque pending state, and per-module conflict resolution builders.
- `lib/src/webdav/sync_engine.dart`: `WebDavSyncEngine` config/base/client-ID persistence, complete
  remote/local upload-lock lifecycle, raw missing/equal fast paths, module merge and one-time local
  re-read, pending/finalize flow, sticky local-change signal, referenced-only additive image sync,
  progress, force upload, and force download. It accepts a WebDAV config per operation so app
  facades can preserve manual sync with unsaved config-page values.
- `lib/src/backup/backup_engine.dart`: `BackupEngine` v2 bundle creation (per-module raw JSON
  strings + `_imageRefs`, no `createdAt`/`modules`), sha256 content-addressed blob store with
  reference-counted GC (10-minute grace, abort-on-unparseable), age-based retention, guarded daily
  auto-backup, corrupt-bundle flagging, validate-before-write v1/v2 restore with the I5
  auto-sync-disable interplay, the synthetic `images` module knob (MyDevice), and the tolerant
  image-key sanitizer (J17).
- `lib/src/data/zip_transfer.dart`: `ZipTransfer` registry-driven ZIP export (module files +
  `images/<basename>`, per-app archive name prefix) and two-phase validated import standardized on
  MyDay's strict traversal rejection, with per-app leniency knobs (`rejectUnknownEntries`,
  `strictUtf8`, `validateBeforeWrite`, `atomicWrites`) and an optional after-import hook.
- `lib/src/sync/auto_sync_scheduler.dart`: `AutoSyncScheduler` lifecycle-observed, debounced
  (30s), periodic (15min) auto-sync core with the `_syncing` guard, in-memory status, reload/status
  listeners, and app hooks (`isAutoSyncActive`, `runSync`, `consumeLocalDataChanged`,
  `onPeriodicTick`, `onResume`) that preserve each app's trigger topology and side effects.

All APIs are exported from `lib/myapps_data.dart` and covered by focused unit tests. 36 package-owned
golden fixtures run the ten characterization sync scenarios plus backup-v2 and ZIP-export format
checks against synthetic MyAnime (1 module), MyDay (5 modules), and MyDevice (4 modules) registries;
the unfiltered CI test command verifies them. See [functions/INDEX.md](functions/INDEX.md) for the
current declaration inventory.

### Integration outcome

All three apps consume this package and shipped on it in `v1.3.0`:

| App | Modules | Engine lines removed | Existing tests |
|---|---|---|---|
| MyAnime | 1 | 2,038 | 56/56 pass unmodified |
| MyDevice | 4 | ~2,000 | 59/59 pass unmodified |
| MyDay | 5 | 3,635 | 132/132 pass unmodified |

Each app keeps its previous public service APIs as thin facades (`WebDAVService`, `BackupService`,
`ImportExportService`, `AutoSyncService`), so no app test needed editing. App-specific behavior that
could not be unified survives as explicit hooks rather than being erased — MyDay's finance
forced-balance migration (`postMergeTransform`), its whole-file exchange-rate merge, its
schema-driven preservation (`preUploadTransform`), and its `ReminderService`-driven daily backup;
MyDevice's `mergeAssignments` and its synthetic `images` backup module.

## How the three apps consume this package

Each app embeds this repository as a git **submodule** at `packages/myapps_data`, using the
relative URL `../MyApps-DATA.git` (so it resolves against whichever host the app itself was cloned
from — Gitea or GitHub), plus a pub **path dependency**:

```yaml
dependencies:
  myapps_data:
    path: packages/myapps_data
```

Because pub does not lock the contents of a path dependency, the submodule commit SHA is the
effective lockfile. Apps pin to a **tagged** release commit before any app release; changes here
must be pushed to both remotes (`origin` and `github`) before any app's submodule pointer is
bumped.

## Conventions inherited from the three apps

- **Function Explanation Layer**: every function, method, constructor, getter, and setter carries
  a structured `/// Purpose: / Inputs: / Returns: / Side effects: / Notes:` doc comment immediately
  above it. This documentation set treats that comment as the first-pass source of truth and reads
  the implementation for anything the comment doesn't fully capture.
- **UTC timestamps** for anything compared across devices.
- **Pretty-printed JSON** via `JsonEncoder.withIndent('  ')`.
- **Unknown JSON fields are preserved** end-to-end through parse → merge → write.
- **No app-specific knowledge** in this package: no app model imports, no hardcoded per-app data
  file lists, no localized user-facing strings. App-specific behavior is injected via
  `DataModule` descriptors and the `StorageAdapter` interface.
- License: GPL-3.0, inherited from the three source apps.

## Documentation maintenance

Once engine code lands in `lib/src/`, every new area must gain a `doc/en-us/functions/` page (and,
once `doc/zh-cn/` exists, the matching Chinese translation) in the same change set — see this
repo's `AGENTS.md` for the exact rule.
