# lib/src/webdav/sync_engine.dart

Generic WebDAV orchestration parameterized by `StorageAdapter`, `ModuleRegistry`, and per-operation
`WebDAVConfig`. It composes P2.4 atomic I/O, P2.5 transport/remote-lock primitives, and app-owned
module callbacks without importing app models.

## Public declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `WebDavClientFactory` | typedef | A | Build a transport bound to the current supplied config. |
| `SyncClock` | typedef | A | Inject UTC time for deterministic lock tests. |
| `SyncIdGenerator` | typedef | A | Inject client-ID/upload-token generation. |
| `EngineSyncResult` | class | A | Return success, joined error, pending state, and warnings. |
| `EnginePendingModule` | class | A | Retain one module descriptor and opaque pending merge outcome. |
| `EnginePendingSync` | class | A | Preserve ordered pending modules and flattened conflicts. |
| `WebDavSyncEngine` | class | A | Run config, sync, finalize, image, and force workflows. |

The index counts 47 declarations including constructors, getters, public operations, and private
state-machine helpers.

## Construction

`WebDavSyncEngine` requires an app storage adapter, ordered module registry, and per-app fallback
remote path. `failFastOnDownloadError` defaults false; MyAnime can set true at integration time.
Client factory, clock, and ID generator are injectable test seams. One long-lived engine per app is
required to preserve the operation guard, progress notifier, and sticky local-change signal.

Public sync/force/finalize methods take `WebDAVConfig` per call. This preserves current manual
operations that use unsaved config-page values rather than silently reloading persisted config.

## Normal sync

The normal flow is:

1. Reject overlapping sync/force work with `Sync already in progress`.
2. Best-effort MKCOL the remote app root.
3. Load/create `.sync_base/client_id.txt` and inspect `upload_lock.json`.
4. Acquire remote `.lock` before any module GET, using strong ETag `If-Match` or
   `If-None-Match: *`; lock PUTs remain retry-exempt.
5. Process modules in registry order.
6. Run referenced-only additive image sync even when modules have conflicts/per-file errors.
7. Release matching remote/local lock state and publish terminal progress.

Per-module branch behavior:

| Local | Remote | Action |
|---|---|---|
| missing | 404 | Skip; retain any stale base. |
| missing | found | Copy remote raw JSON locally and to base; no module parse. |
| present | 404 | Force-upload local raw JSON, then save base. |
| present | byte-identical | Save raw base; no merge/upload. |
| present | differing | Read base, invoke module merge, re-read local once if initially conflict-free, then pending or transform/write/upload/base. |
| any | non-404 error | Per-file error and continue, unless fail-fast is configured. |

Merged local JSON is written before PUT, but its base changes only after successful PUT. A failed
upload therefore leaves the new local data and sticky local-change signal with the old base, so the
next sync re-merges.

## Pending and finalize

Conflict-only sync can be `success: true` with non-null pending state, matching existing apps.
Finalization reacquires `.lock`, uses each module's resolution builder and post-merge transform,
freshly downloads the remote module, applies optional preservation context, writes local, uploads,
and saves base on success.

Compatibility limits are deliberate: finalize does not share the sync/force guard, does not emit
progress, and does not re-merge known fields changed while dialogs were open. Its fresh GET prevents
upload over an unreadable remote and supplies MyDay preservation context. These are existing app
semantics; changing them is outside the zero-change extraction.

## Images

Image references are accumulated in registry order, local then remote for each module. Normal sync
MKCOLs and PROPFINDs `images/`; a listing failure skips the phase with the fixed warning. Otherwise
it uploads referenced local names missing remotely, then downloads referenced remote names missing
locally in reference order. Same-name files and orphans are never overwritten or deleted.

Force upload falls back to uploading every referenced local image when listing fails. Force
download is lock-free, downloads only referenced remote images, and reports a fixed warning when
listing fails.

## Force operations

`forceUpload` holds `.lock`, uploads each existing local module raw without validation/merge, saves
base after each successful PUT, skips missing local modules, and aborts on the first data failure.

`forceDownload` takes no lock, downloads in registry order, keeps local/base on remote 404, performs
only `jsonDecode` syntax checking, atomically writes raw remote JSON and base incrementally, and
retains earlier writes when a later module fails.

## Local state

`loadConfig` applies `defaultRemotePath` only when the key is missing/null; an explicit empty path
remains the WebDAV account root. Config JSON stays compact. Base reads swallow errors as no-base;
writes use P2.4 atomic replacement. `consumeLocalDataChanged` is read-and-reset and means "changed
since last consume," not only the most recent operation.
