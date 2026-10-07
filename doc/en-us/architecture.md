# Architecture

## What this package is

`myapps_data` is the shared Flutter package holding the WebDAV sync engine and the data-management
engine (backup/restore, ZIP import/export, and the plumbing they share). Applications
integrate through module descriptors, storage adapters and domain callbacks.

The package centralizes reusable service logic that applications can expose through facades:

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
UI, storage hub, and app-specific merge wrappers. Record concrete integrations and
validation in each application's documentation.

## The behavior contract

Read [invariants.md](invariants.md) before doing any structural work here. It holds:

- The **hard invariants** (I1–I10) that this package must preserve — the WebDAV wire format, lock
  semantics (60-second TTL, 20-second heartbeat), the rule that restoring a backup disables auto-sync
  before the first write, the facade rule that keeps every app test passing, and the rule that the
  real Gitea host is never committed anywhere.
- The **unification rule** and the list of accepted unifications, each with its behavioral
  consequence.

For shared behavior and configurable policies, see [feature-matrix.md](feature-matrix.md).

## Package layout

Common data-management settings presentation lives in `lib/src/settings/`.
WebDAV connection fields, save/test controls, manual/force sync controls,
automatic-sync preference and disconnect affordances are shared. Applications
inject domain-specific content and retain operation and confirmation callbacks.
Action tiles and backup preferences accept application labels, status and callbacks;
the package owns their presentation while applications retain routes and storage.
The WebDAV privacy notice, its paused-sync banner and the per-device acknowledgement
contract are shared; applications supply the data inventory, labels, notice version and
persistence, and decide when to pause sync.

`lib/src/` is organized by area: `storage/` (`StorageAdapter`, atomic I/O), `json/` (JSON-preservation
engines), `merge/` (`mergeRecords<T>`), `modules/` (`DataModule`/`ModuleRegistry`), `webdav/` (config,
client, upload lock, sync engine, progress), `sync/` (auto-sync scheduler, wake lock), `backup/`
(backup engine), `data/` (ZIP transfer), `secrets/` (secrets file, store, exchange). The public API is exported only through
`lib/myapps_data.dart`; consumers must not import `src/` paths directly.

## Current state (complete and in production)

Every engine area below is implemented and unit-tested. Progress and wake-lock helpers include:

- `lib/src/webdav/sync_progress.dart`: shared progress phases, immutable progress snapshots, and
  the `ValueListenable` type alias consumed by app UIs.
- `lib/src/sync/sync_wake_lock.dart`: the reference-counted, ownership-safe foreground sync wake
  lock. It never disables a lock owned by another feature and treats plugin failures as best-effort.

The remaining engine areas provide:

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
  auto-sync-disable interplay, the synthetic `images` module knob, and the tolerant
  image-key sanitizer (J17).
- `lib/src/data/zip_transfer.dart`: `ZipTransfer` registry-driven ZIP export (module files +
  `images/<basename>`, per-app archive name prefix) and two-phase validated import standardized on
  strict traversal rejection, with configurable leniency knobs (`rejectUnknownEntries`,
  `strictUtf8`, `validateBeforeWrite`, `atomicWrites`) and an optional after-import hook.
- `lib/src/sync/auto_sync_scheduler.dart`: `AutoSyncScheduler` lifecycle-observed, debounced
  (30s), periodic (15min) auto-sync core with the `_syncing` guard, in-memory status, reload/status
  listeners, and app hooks (`isAutoSyncActive`, `runSync`, `consumeLocalDataChanged`,
  `onPeriodicTick`, `onResume`) that preserve each app's trigger topology and side effects.
- `lib/src/webdav/endpoint_security.dart`: the pure secure-endpoint policy
  (`evaluateEndpointSecurity`/`evaluateEndpointUrl`) with a named reason and transport class for
  every verdict, shared by the privacy notice and secret channels. HTTPS, private networks,
  Tailscale `*.ts.net` and EasyTier `*.et.net` pass by default; a plain-HTTP public host passes
  only through the device-local trusted list, which applications extend only after
  `showMyAppsTrustedHostWarning` (`lib/src/settings/trusted_host_warning.dart`) is confirmed.
- `lib/src/webdav/privacy_acknowledgement.dart`: the per-device privacy-notice acknowledgement
  record, `needsAcknowledgement`, the `WebDavPrivacyStatus` gate and an injected-persistence store.
  The record is never a data module.
- `lib/src/secrets/`: the generic API-key secret channel. `SecretsDocument` is the secrets-file
  shape with a per-key last-writer-wins merge and tombstones; `SecretStore` reads and writes one
  application's file (name injected, keys restricted to declared namespaces) under an in-app lock,
  sets unparseable content aside and raises `SecretsUnreadableException` for I/O errors;
  `SecretExchange` exchanges the file after a sync, gated by the secure-endpoint policy in both
  directions, with conditional upload and one re-read and re-merge. The file is never a data module,
  so backups and ZIP exports never contain it.

All APIs are exported from `lib/myapps_data.dart` and covered by focused unit tests. 36 package-owned
golden fixtures run the ten characterization sync scenarios plus backup-v2 and ZIP-export format
checks against synthetic registries containing 1, 5 and 4 modules;
the unfiltered CI test command verifies them. See [functions/INDEX.md](functions/INDEX.md) for the
current declaration inventory.

### Application boundaries

Applications may retain public service APIs as thin facades. Domain merge policies,
post-merge migrations, pre-upload preservation, backup triggers and image selection
remain application-owned and enter through explicit hooks.

## How applications integrate this package

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

## Conventions

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
- License: GPL-3.0.

## Documentation maintenance

Once engine code lands in `lib/src/`, every new area must gain a `doc/en-us/functions/` page (and,
once `doc/zh-cn/` exists, the matching Chinese translation) in the same change set — see this
repo's `AGENTS.md` for the exact rule.
