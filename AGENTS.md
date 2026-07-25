# AGENTS.md — myapps_data (MyApps-DATA)

## What this is

`myapps_data` is the shared WebDAV-sync and data-management (backup/restore, ZIP
import/export) Flutter package consumed by three sibling apps: **MyAnime**, **MyDay**,
and **MyDevice**. It exists to replace their hand-ported, drifted copies of
`lib/shared/services/{webdav_service,sync_merge,sync_progress,sync_wake_lock,auto_sync_service,backup_service,import_export_service}.dart`.

The authoritative extraction plan lives in the local workspace root as `PLAN.md`
(sibling of the app checkouts, not inside any repo). Read it before doing structural
work here. The behavior contract is its "hard invariants" table (I1–I10); the
per-behavior reference is `docs/feature-matrix.md` (produced by plan task P0.1 —
if it does not exist yet, that task has not run).

## Repository & remotes

- `origin` -> `<local_gitea_address>` (private Gitea; the real address is deliberately
  **never** written in committed files — find it via `git remote -v` in any sibling repo).
- `github` -> `git@github.com:YuanZhe-99/MyApps-DATA.git` (public mirror; app CI fetches
  the submodule from here).

**Masking rule:** never commit the real Gitea host/port anywhere in this repo — docs,
comments, CI, `.gitmodules` (consumers use the relative URL `../MyApps-DATA.git`).

## How the apps consume this package

Each app embeds this repo as a git submodule at `packages/myapps_data` (relative URL
`../MyApps-DATA.git`, so it resolves against whichever host the app was cloned from)
plus a pub path dependency. **The submodule commit SHA is the lockfile** — pub does not
lock path-dependency contents.

Rules:
- Push changes here to **both** remotes *before* bumping any app's submodule pointer.
- Apps must pin to a **tagged** commit before any app release.
- Releases: semver, `CHANGELOG.md` entry, tag `vX.Y.Z` pushed to both remotes.

## Conventions (inherited from the three apps — mandatory)

- **Function Explanation Layer**: every function/method/constructor/getter/setter carries
  a structured doc comment immediately above it:
  `/// Purpose: … / Inputs: … / Returns: … / Side effects: … / Notes: …`.
  Agents investigating this codebase read comments/signatures first, source bodies only
  when necessary.
- **UTC timestamps**: anything compared across devices (`modifiedAt`, lock timestamps)
  uses `DateTime.now().toUtc()`. Local-time values break sync conflict detection.
- **JSON output** is pretty-printed via `JsonEncoder.withIndent('  ')`.
- **Unknown JSON fields are preserved** end-to-end (parse → merge → write). Never drop
  fields this package doesn't model.
- **No app-specific knowledge**: no app model imports, no hardcoded data-file lists, no
  user-facing localized strings. Everything app-specific arrives via `DataModule`
  descriptors and the `StorageAdapter` interface (see PLAN.md §3.2).
- Lints: `flutter_lints` baseline (`analysis_options.yaml`), no custom overrides.
- License: GPL-3.0 (code originates from the GPL-3.0 apps).

## Documentation Maintenance

`doc/en-us/` holds this package's documentation: `architecture.md` (what this is, target shape,
how apps will consume it), `translation-guide.md` (the English-to-Chinese glossary and style
guide, kept byte-identical across this repo and its siblings MyAnime/MyDay/MyDevice), and
`functions/` (one page per source file, mirroring `lib/`, listing every declaration).

Any change that adds, removes, or changes the behavior/signature of a function must update the
corresponding page(s) under `doc/en-us/` in the same commit: the per-file page under
`doc/en-us/functions/`, its `INDEX.md` row, and `architecture.md` if the change affects the
package's shape or consumption model. Once `doc/zh-cn/` exists, it must mirror `doc/en-us/`
exactly and gets updated in the same commit too, translated per `translation-guide.md`; new
terminology goes into the glossary in all four sibling repos, not just this one. Never write the
real Gitea host in documentation — always `<local_gitea_address>`.

## Layout (target — see PLAN.md §3.1)

`lib/src/` areas: `storage/` (StorageAdapter, atomic I/O), `json/` (generic preservation
engine), `merge/` (generic `mergeRecords<T>`), `modules/` (DataModule/ModuleRegistry),
`webdav/` (config, client, lock, sync engine, progress), `sync/` (auto-sync scheduler,
wake lock), `backup/`, `data/` (ZIP transfer). Public API is exported only through
`lib/myapps_data.dart`.

Current implementation status: P2.1-P2.10 are complete. `lib/src/webdav/sync_progress.dart`
and `lib/src/sync/sync_wake_lock.dart` are byte-identical moves from all three apps;
`lib/src/json/json_preservation.dart` (schema-driven + flat-map preservation) and
`lib/src/merge/sync_merge.dart` (generic `mergeRecords<T>`) are exported and unit-tested.
`lib/src/storage/atomic_io.dart` provides atomic string/byte replacement and optional
per-owner write serialization. `lib/src/webdav/webdav_config.dart` provides the shared
`WebDAVConfig`; `lib/src/webdav/upload_lock.dart` provides `WebDAVUploadLock` and
`UploadSession`; `lib/src/webdav/webdav_client.dart` provides the pure `WebDavClient`
transport (verbs, auth, retry, remote lock primitives, heartbeat).
`lib/src/storage/storage_adapter.dart`, `lib/src/modules/data_module.dart`, and
`lib/src/webdav/sync_engine.dart` provide the app-neutral module registry and complete
sync/lock/base/image/force orchestration. `lib/src/backup/backup_engine.dart` provides
the generic backup engine: v2 bundles, sha256 blob store with reference-counted GC,
retention, guarded daily auto-backup, and validate-before-write v1/v2 restore with the
I5 auto-sync-disable interplay. `lib/src/data/zip_transfer.dart` provides the
registry-driven ZIP transfer engine: export of module files plus `images/<basename>`
with per-app archive prefixes, and a two-phase traversal-safe import standardized on
MyDay's strict semantics with per-app leniency knobs. `lib/src/sync/auto_sync_scheduler.dart`
provides the lifecycle-observed, debounced, periodic auto-sync core with the `_syncing` guard,
in-memory status, reload/status listeners, and app hooks (`isAutoSyncActive`, `runSync`,
`consumeLocalDataChanged`, `onPeriodicTick`, `onResume`) preserving each app's trigger topology
and side effects. `test/golden/shared_engines_golden_test.dart` replays the ten P0.2 sync
scenarios plus backup-v2 and ZIP-export format fixtures against synthetic 1/5/4-module
MyAnime/MyDay/MyDevice registries. Its 36 package-owned goldens run in verify mode as part of
the unfiltered CI test command. The Phase 2 implementation gate is complete; tagging and pushing
the planned pre-integration `v0.9.0` release requires explicit user authorization.

## Verification

```
flutter pub get
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yml`, GitHub only) runs all three on every push/PR to `main`
with Flutter 3.44.2 — stricter than the apps on purpose; this is the load-bearing layer.

## Never commit

Secrets, WebDAV credentials or test-server configs with real hosts, signing keys, the
real Gitea address, `pubspec.lock` (library package), or golden files containing
personal data from the apps.
