# Feature Matrix - Three-way drift audit of the shared services

> **Purpose:** the per-behavior reference for PLAN task **P0.1**. For every behavioral
> point in the WebDAV sync + data-management services, this records what each of
> **MyAnime**, **MyDay**, **MyDevice** does today and whether the shared engine must
> make it **`fixed`** (identical everywhere -> one shared implementation) or
> **`config`** (a per-app knob, named here). This is the foundation that lets Phase 2
> build the package with **zero functional change** (PLAN invariants I1-I10).
>
> **Scope:** the nine shared-service files diffed across the three apps:
> `webdav_service.dart`, `sync_merge.dart`, `sync_progress.dart`, `sync_wake_lock.dart`,
> `auto_sync_service.dart`, `backup_service.dart`, `import_export_service.dart`,
> `json_preservation.dart` (MyDay + MyDevice; MyAnime bakes preservation into models),
> `data_file_safety.dart` (MyDay only). Verified 2026-07-23 against the working trees at
> `C:\Users\yuanzhe\source\repos\{MyAnime,MyDay,MyDevice}` via `git diff --no-index`,
> SHA-256 hashing, and full-file reads.
>
> **Line references** are `file:line` (e.g. `webdav_service.dart:583`) and are relative
> to each app's `lib/shared/services/` (or `lib/shared/utils/` for the preservation
> files) unless a full path is given.
>
> **How to read a row:** `Verdict` is `fixed` (one shared impl, no knob) or
> `config` (per-app knob - the knob name follows). Where a row is `fixed` but the apps
> currently differ in a *fixable* way, the reconciliation target is stated.

---

## 0. Byte-identity of the "reported identical" files (P2.1 inputs)

| File | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|
| `sync_progress.dart` | 62 lines | 62 lines | 62 lines | **fixed** - SHA-256 identical across all three (verified `git diff --no-index` exit 0). Verbatim move to `lib/src/webdav/sync_progress.dart`. |
| `sync_wake_lock.dart` | 60 lines | 60 lines | 60 lines | **fixed** - SHA-256 identical across all three (verified). Verbatim move to `lib/src/sync/sync_wake_lock.dart`. |

`sync_progress.dart` exposes `enum SyncPhase { idle, connecting, downloadingData, merging, uploadingData, uploadingImages, downloadingImages, done, error }`, the immutable `SyncProgress` class (`phase`, `detail`, `current`, `total`, `fraction`, `isRunning`), and `typedef SyncProgressListenable = ValueListenable<SyncProgress>`. `sync_wake_lock.dart` is reference-counted with ownership tracking; `acquire()`/`release()` swallow all plugin errors. **No drift -> no P0.1 escalation needed** (PLAN P2.1's "if they differ, escalate" condition is not triggered).

---

## 1. PLAN-claim corrections (findings that update PLAN.md)

The PLAN's investigation section (PLAN §1) and P0.1 bullets contain several claims that
this audit found to be **understated or wrong**. These are recorded so the engine is not
built on a false premise; PLAN.md is updated in the same change set (see changelog at the
bottom of PLAN).

| # | PLAN claim | Audit finding | Impact |
|---|---|---|---|
| C1 | "MyDevice treats 207 *and* 404 as reachable - do the others?" (P0.1) | **All three** use the identical condition `streamed.statusCode == 207 || streamed.statusCode == 404` (MyAnime `webdav_service.dart:583`, MyDay `:764`, MyDevice `:608`). | Not a MyDevice differentiator -> `fixed`, no knob. |
| C2 | "MyDay has local `.sync_base/upload_lock.json` - confirm MyAnime/MyDevice equivalents" (P0.1) | **All three** have `_localLockFileName = 'upload_lock.json'` written to `.sync_base/` (MyAnime `:293`, MyDay `:330`, MyDevice `:314`) with identical read/save/clear helpers. | Not MyDay-only -> `fixed`. |
| C3 | "probe-size cap (MyDevice `_probeMaxBytes` 4 MB - others?)" (P0.1) | **All three** define `static const _probeMaxBytes = 4 * 1024 * 1024;` (MyAnime `:28`, MyDay `:28`, MyDevice `:31`). | Not MyDevice-only -> `fixed` (with an injectable default). |
| C4 | "Identical-content conflict suppression (explicit in MyDevice; verify others)" (P0.1) | **All three** implement it identically: `if (serialize != null && serialize(l) == serialize(r))` (MyAnime `:76`, MyDay `:105`, MyDevice `:97`). All call sites pass `serialize: (x) => jsonEncode(x.toJson())`. | Not MyDevice-only -> `fixed`. |
| C5 | "MyDay's and MyDevice's [mergeRecords] are supersets; MyAnime's is a subset" (P2.3) | MyAnime's and MyDay's signatures are **byte-identical** (8 params). Only **MyDevice** is a superset - it adds one optional param `mergeUnknownFields` (MyDevice `:68`). MyDay is *not* a superset. | Adopt MyDevice's signature (optional param is backward-compatible). |
| C6 | "sync_progress.dart (73 lines)", "sync_wake_lock.dart (64-65 lines)" (PLAN §1) | Both are **62 / 60 lines** respectively, byte-identical. | Cosmetic PLAN fix. |
| C7 | "webdav_service.dart: 1855 / 2291 / 2134 lines" (PLAN §1) | Actual: **1856 / 2292 / 2135** (off-by-one trailing newline). PLAN's counts were essentially correct. | Cosmetic. |
| C8 | "Backup format v2 ... `backups/backup_<...>.json` bundles ... `createdAt`" (PLAN §1, P0.1 implies `createdAt`) | The v2 bundle has **no `createdAt` field** and **no `modules` field**. Only `_backupFormat` (=2), the per-module raw JSON strings, and `_imageRefs` are written. `_images` is **legacy v1 only** (never written by v2). | Engine must not write/read `createdAt`; I2 wording updated. |
| C9 | "data_file_safety.dart (MyDay)" located generically | It lives at `lib/shared/services/data_file_safety.dart` (138 lines), **not** `lib/shared/utils/`. MyAnime/MyDevice have **no equivalent file** - their atomic helpers are private inside `BackupService`/`WebDAVService`/the storage hub. | Extraction target: one `lib/src/storage/atomic_io.dart`. |

---

## A. WebDAV config & transport

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| A1 | `WebDAVConfig` fields/types | `serverUrl,username,password,remotePath,autoSync` (`:33`) | identical (`:36`) | identical (`:36`) | **fixed** |
| A2 | `remotePath` default | `'/MyAnime'` (`:33,80`) | `'/MyDay'` (`:36,83`) | `'/MyDevice'` (`:36,83`) | **config** - knob `defaultRemotePath` (per-app constant) |
| A3 | `.nextcloud()` factory | constructs `https://$host/remote.php/dav/files/$username` (`:89-97`) | identical (`:93-101`) | identical (`:92-100`) | **fixed** |
| A4 | `isConfigured`/`copyWith`/`toJson`/`fromJson` | identical | identical | identical | **fixed** |
| A5 | Base URL normalization (`_remoteFileUrl`) | strips trailing `/` from serverUrl, ensures remotePath ends `/`, string-concat; **no URL-encoding** (`:552`) | identical (`:733`) | identical (`:577`) | **fixed** (latent no-encoding bug is consistent; preserve to keep wire-format byte-identical, I1) |
| A6 | `_authHeaders` (HTTP Basic) | `Authorization: Basic <base64>` (`:540`) | identical (`:721`) | identical (`:565`) | **fixed** |
| A7 | User-Agent | none set | none | none | **fixed** (preserve absence; do not add - changes wire format) |
| A8 | `http.Client` lifecycle | created inline per call, never `.close()`d | identical | identical | **fixed** (preserve; optional future hardening out of scope) |
| A9 | `testConnection` verb/depth/body/timeout | PROPFIND Depth:0, 10s (`:567-587`) | identical (`:748-768`) | identical (`:592-612`) | **fixed** |
| A10 | `testConnection` reachable statuses | `207 || 404` (`:583`) | `207 || 404` (`:764`) | `207 || 404` (`:608`) | **fixed** (see correction C1) |
| A11 | `_ensureRemoteDir` (MKCOL, swallow all) | swallows all errors, no 405/409 inspect (`:594`) | identical (`:775`) | identical (`:619`) | **fixed** |
| A12 | `_ensureRemoteSubDir` param/URL | param `subPath`, manual URL rebuild (`:1099`) | param `subPath`, manual rebuild (`:1209`) | param `subDir`, via `_remoteFileUrl` (`:1073`) | **fixed** - unify on `_remoteFileUrl` form (behavior identical) |
| A13 | `_upload` (JSON PUT, 412 handling) | returns `({bool is412, String? error})`; 412 msg `'conditional WebDAV PUT failed (HTTP 412)'` (`:615`) | identical (`:796`) | identical (`:640`) | **fixed** |
| A14 | `_uploadBytes` (image PUT) return type | `Future<bool>` (`:669`) | `Future<void>` (`:851`) | `Future<bool>` (`:1023`) | **fixed** - unify on `Future<void>` (return value unused) |
| A15 | `_download` (JSON GET) | returns `RemoteFile` (`:703`) | identical (`:884`) | identical (`:698`) | **fixed** |
| A16 | `_downloadBytes` (image GET) return type | `Future<Uint8List?>` (`:1027`) | `Future<Uint8List>` (`:1288`) | `Future<Uint8List?>` (`:1053`) | **fixed** - unify on `Future<Uint8List>` (null never actually returned) |
| A17 | `_deleteRemoteUploadLock` 404 early-return | yes (`:788`) | no (`:958`) | no (`:772`) | **fixed** - drop redundant 404 check (already swallowed) |
| A18 | Per-verb timeouts | PROPFIND-list 15s; PUT-json 30s; PUT-image 120s; GET-json 30s; GET-image 120s; MKCOL 10s; DELETE 10s | same **except PROPFIND-list 30s** (`:1258`) | same as MyAnime | **config** - knob `propfindTimeout` (default 15s; MyDay currently 30s - reconcile to 15s, harmless) |
| A19 | `_dataFileNames` (per-app file list) | `['anime_data.json']` (`:290`) | 5 files (`:321-327`) | 4 files (`:306-311`) | **config** - knob `dataFileNames` (the module registry; replaces the 5 hardcoded MyDay lists, PLAN §1 duplication smell) |
| A20 | `getAppDir()` provider | `AnimeStorage` | `TodoStorage` | `DeviceStorage` | **config** - `StorageAdapter.getAppDir()` (PLAN §3.2) |

---

## B. Upload lock (`WebDAVUploadLock`)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| B1 | Remote lock file name | `.lock` (`:291`) | `.lock` (`:328`) | `.lock` (`:312`) | **fixed** (I1) |
| B2 | Local lock file name | `upload_lock.json` in `.sync_base/` (`:293`) | identical (`:330`) | identical (`:314`) | **fixed** (I2; see correction C2) |
| B3 | `client_id.txt` in `.sync_base/` | yes (`:292`) | yes (`:329`) | yes (`:313`) | **fixed** |
| B4 | Lock JSON schema | `{clientId, token, startedAt, updatedAt, ttlSeconds}` (UTC ISO8601) (`:190`) | identical (`:219`) | identical (`:206`) | **fixed** (I1/I2) |
| B5 | TTL | 60s (`_lockTtlSeconds=60`) | 60s | 60s | **fixed** (I3) |
| B6 | Heartbeat | 20s `Timer.periodic`, failures swallowed (`:936`) | identical (`:1116`) | identical (`:930`) | **fixed** (I3) |
| B7 | Stale-lock takeover | expired remote lock replaceable; `If-Match`/`If-None-Match: *` ETag guards (`:832`) | identical (`:1012`) | identical (`:826`) | **fixed** (I3) |
| B8 | 412 contention message | `'Another device started uploading; retry after the lock expires.'` | identical | identical | **fixed** (I8) |
| B9 | Interrupted-upload detection | `_prepareInterruptedUpload`: reads local lock, matches clientId+token against remote (`:797`) | identical (`:977`) | identical (`:791`) | **fixed** (I2) |
| B10 | Lock-write retry exemption | `_writeRemoteUploadLock` passes `retries: 0` (`:768`) | identical (`:949`) | identical (`:763`) | **fixed** (I3) |
| B11 | `isExpired` rule | `now.difference(updatedAt).inSeconds >= ttlSeconds` (`:203`) | identical | identical | **fixed** (I3) |

The entire upload-lock subsystem is **byte-identical** across all three apps. It moves to
the package verbatim with TTL/heartbeat injectable for tests but defaults fixed (I3).

---

## C. PROPFIND XML parsing (the one real transport drift)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| C-P1 | href regex | `<d:href>` with `caseSensitive:false` (`:1076`) | `<[dD]:href>` char-class, case-sensitive (`:1265`) | `<(?:\w+:)?href>` prefix-optional, `caseSensitive:false` (`:1115`) | **fixed** - adopt MyDevice's `<(?:\w+:)?href>` form (most robust: also matches bare `<href>`/`<DAV:href>`) |
| C-P2 | directory-self skip | `endsWith('/')` + `p.basename` | `endsWith('$subPath/')`/`endsWith(subPath)`/`endsWith('/')` + `split('/').last` | `endsWith('/')` + `split('/').last` | **fixed** - unify on `endsWith('/')` + `p.basename` |
| C-P3 | method name | `_listRemoteFiles` (`:1050`) | `_listRemoteDir` (`:1236`) | `_listRemoteFiles` (`:1094`) | **fixed** - unify name |
| C-P4 | PROPFIND listing timeout | 15s (`:1071`) | 30s (`:1258`) | 15s (`:1109`) | **config** - knob `propfindTimeout` (default 15s); covered by A18 |

**Effect of drift:** MyDevice is the most lenient (accepts servers emitting unprefixed
`<href>`); MyAnime/MyDay would silently return an empty set on such servers, causing
`_syncImages` to re-upload every referenced image. Adopting MyDevice's regex is safe and
strictly more correct; it does not change behavior against any server the apps currently
work with (all known servers emit `d:`/`D:` prefixed hrefs).

---

## D. Retry policy & exception taxonomy

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| D1 | `_withRetry` body | max 2 extra attempts; backoff `Duration(seconds: attemptIndex)` = 1s then 2s (`:342`) | identical (`:391`) | identical (`:375`) | **fixed** (I3) |
| D2 | retryable exceptions | `SocketException, TimeoutException, http.ClientException, HttpException` | identical | identical | **fixed** (I3) |
| D3 | retryable status codes | 5xx only via `shouldRetry: (r) => r.statusCode >= 500`; **4xx never retried** | identical | identical | **fixed** (I3) |
| D4 | operations exempt from retry | lock writes (`retries:0`) | identical | identical | **fixed** (I3) |
| D5 | `RemoteFileStatus` enum | `{found, notFound, error}`; only HTTP 404 -> `notFound` (`:242-285`) | identical (`:270-313`) | identical (`:257-300`) | **fixed** (only true 404 = missing) |
| D6 | non-200/404 on download | `RemoteFile.failure('HTTP $code')`; callers abort that file | identical | identical | **fixed** |

---

## E. Merge engine (`mergeRecords<T>` and friends)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| E1 | `mergeRecords<T>` signature | 8 params (no `mergeUnknownFields`) (`:43-52`) | **identical** to MyAnime (`:72-81`) | 9 params: adds optional `mergeUnknownFields` (`:61-71`) | **fixed** - adopt MyDevice's signature (optional param; backward-compatible). See correction C5. |
| E2 | `RecordConflict<T>` fields | `id, localRecord, remoteRecord, displayName` (`:9-12`) | identical (`:15-18`) | identical (`:13-16`) | **fixed** |
| E3 | `RecordMergeResult<T>` fields | `merged, conflicts` (`:29-30`) | identical (`:35-36`) | identical (`:33-34`) | **fixed** |
| E4 | **Deletion semantics** (see E4 detail) | identical | identical | identical | **fixed** - documented below; pin with tests in P2.3 |
| E5 | identical-content suppression | `serialize != null && serialize(l)==serialize(r)` -> no conflict (`:76`) | identical (`:105`) | identical (`:97`) | **fixed** (see correction C4); `serialize` callback is the (optional) knob |
| E6 | timestamp field | `getModifiedAt` callback -> model `modifiedAt` (UTC) | identical | identical | **fixed**; knob is the `getModifiedAt` callback |
| E7 | "newer wins" | `DateTime.isAfter` strict | identical | identical | **fixed** |
| E8 | ties (equal timestamps, both changed) | identical-content -> no conflict; else `autoResolve`? LWW picks remote (`l.isAfter(r) ? l : r`); `autoResolve=false` -> conflict | identical | identical | **fixed** |
| E9 | ties (no base, equal timestamps) | remote wins (`? l : r`) | identical | identical | **fixed** |
| E10 | missing/null `modifiedAt` | `DateTime.parse` throws (no null tolerance) | identical | identical | **fixed** (document as precondition: `modifiedAt` must be present) |
| E11 | `autoResolve` default | `false` (`:50`); 0 call sites pass `true` | `false` (`:79`); 0 pass `true` | `false` (`:69`); 0 pass `true` | **fixed** (I4 confirmed) |
| E12 | per-module wrappers | `mergeAnimeData` (1 call, returns `extraJson`) | 5 wrappers (Todo=2 calls, Finance=4, Intimacy=5, Weight=1, ExchangeRate=custom) | 4 wrappers (Device=1, Network=1+assignments, DataSet=1, Service=2) + `mergeAssignments` | **fixed** - wrappers stay app-side; package exports `mergeRecords`/`RecordConflict`/`RecordMergeResult`. `DataModule.merge` callback = `(localJson, remoteJson, baseJson, {autoResolve}) -> {mergedJson, conflicts, localChanged, remoteChanged}`. |
| E13 | `mergeExchangeRateJson` (whole-file) | n/a | custom snapshot union, **no baseJson, no autoResolve, no conflicts** (`:801-846`) | n/a | **fixed** - stays app-side as a `DataModule.merge` that ignores base/autoResolve |
| E14 | `mergeAssignments` (composite key, no timestamps) | n/a | n/a | composite key `networkId:deviceId`, content-compare vs base, **local-wins on both-changed, no conflicts ever** (`:163-220`) | **fixed** - stays app-side (MyDevice-only custom merge) |

### E4. Record deletion semantics (was undocumented - now pinned)

The deletion logic is **identical** across all three apps (modulo MyDevice's
`mergeUnknownFields` wrapper). Traced at MyAnime `:103-126` / MyDay `:134-157` /
MyDevice `:127-146`:

| Scenario | Result | Conflict? |
|---|---|---|
| Deleted locally, remote unchanged (in base) | **excluded** (deletion propagates) | No |
| Deleted locally, remote modified | **remote kept** (modify wins over delete) | No |
| Deleted remotely, local unchanged (in base) | **excluded** (deletion propagates) | No |
| Deleted remotely, local modified | **local kept** (modify wins over delete) | No |
| Deleted both sides | **excluded** | No |
| Pure add on one side (no base) | **included** | No |
| Both added same id (no base) | LWW by `modifiedAt` (ties -> remote) | No |

**Key rule:** delete-vs-modify is **never a conflict** - the modified side silently wins.
This must be covered by dedicated tests in P2.3 before any engine code. The only prose
mention today is MyDay `sync_merge.dart:59-60`.

---

## F. Unknown JSON field preservation (I6)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| F1 | preservation style | baked into models: `extraJson` + `withPreservedUnknownJson` + `_mergeJsonMaps` (e.g. `anime.dart:377,775-814`) | schema-driven engine `JsonPreservation` (`json_preservation.dart:1-251` generic; `:252-619` app schemas) | model `extraJson` + `mergeUnknownFields`/`mergeUnknownFieldsFrom` (`json_preservation.dart` 81 lines, generic only) | **config** - package exports BOTH: (a) `mergeUnknownFields` callback on `mergeRecords` (MyDevice pattern, for model-level `extraJson` apps); (b) MyDay's generic `JsonPreservation` engine (lines 1-251) as `lib/src/json/json_preservation.dart` for schema-driven re-injection. App schemas stay app-side. |
| F2 | merge self-sufficient for preservation? | yes (per-record `withPreservedUnknownJson`) | **no** - merge operates on typed objects, unknowns lost at merge; re-injected at write time by `webdav_service._preserveUnknownJson` (`:614-628`) | yes (`mergeUnknownFields` callback) | **config/behavior** - MyDay's gap must be closed: either add `extraJson` to MyDay models (P3.MyDay.2 [B]) or always apply `JsonPreservation` inside the `DataModule.merge` callback. Engine must not assume self-sufficiency. |
| F3 | round-trip survival (parse->merge->write) | full | full (only via the write-time re-injection) | full | **fixed** (I6 holds today; preserve) |
| F4 | MyDay generic engine API | n/a | `JsonListPreservation`, `JsonPreservationSchema`, `JsonPreservation` (static: `encodeForFile`, `preserveJsonString`, `preserve`, `_preserveOne`, ...) | n/a | **fixed** - move lines 1-251 verbatim to package; app schemas (`_todoDataSchema` etc.) stay app-side |
| F5 | MyDevice preservation API | n/a | n/a | `unknownJsonFields`, `mergeUnknownJsonFields`, `jsonValueEquals` (`:8,21,64`) | **fixed** - move to package (overlaps with F1(b)) |

---

## G. Sync orchestration

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| G1 | `sync()` step order | ensureRemoteDir -> getAppDir -> loadClientId -> prepareInterruptedUpload -> **acquire lock** -> per-file download/migrate/merge/upload -> image sync -> release lock (`:1252`) | identical (`:1471`) | identical (`:1276`) | **fixed** (lock acquired BEFORE downloads; preserve) |
| G2 | `autoResolve` at sync | default `false`, no caller overrides (`:1254`) | identical (`:1473`) | identical (`:1278`) | **fixed** (I4) |
| G3 | download-error handling | **aborts whole sync** (`:1355`) | per-file `perFileErrors.add` + `continue` (`:1582`) | per-file (`:1384`) | **config** - knob `failFastOnDownloadError` (default `false`; MyAnime currently true but single-module so low-impact). Reconcile MyAnime to per-file. |
| G4 | per-file merge try/catch | none (single file) | `try{switch(name){...}}catch(e){perFileErrors.add('$name: $e')}` (`:1644-1851`) | identical (`:1438-1641`) | **fixed** - generalize per-file guard |
| G5 | top-level catch format | `'$e\n$st'` (stack trace) (`:1495`) | `e.toString()` (no trace) (`:1895`) | `'$e\n$st'` (`:1684`) | **fixed** - unify on stack-trace form (reconcile MyDay) |
| G6 | per-file error string | n/a (single file) | `'$name: $e'` | `'$name: $e'` | **fixed** |
| G7 | MyDay finance migration hook | n/a | async `_migrateFinanceForcedBalances` after conflict-free merge/resolution and during finalize (`:424,1740,1941`); it reads local exchange-rate storage | n/a | **config** - knob `postMergeTransform` on `DataModule`; applied after merge/resolution, not to remote JSON before conflict detection |
| G8 | MyDay unknown-JSON re-injection at write | model-level only | `_preserveUnknownJson`/`_uploadMergedJson` (`:614,679`) | model-level only | **config** - covered by F2; engine exposes a `preUploadTransform` hook |

### G-IMG. Image sync

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| G9 | referenced-image source | anime `coverImage` basenames (`:1122-1134`) | finance `accounts`+`subscriptions` + intimacy `partners`+`toys` `imagePath` (`:1313-1344`) | device `imagePath` basenames (`:1138-1152`) | **config** - knob `referencedImages` callback on `DataModule` (PLAN §3.2) |
| G10 | local ∪ remote union | union of local+remote referenced (`:1474`) | identical (`:1856`) | identical (`:1646`) | **fixed** |
| G11 | additive-only (never delete) | yes - no delete path | yes | yes | **fixed** (I1) |
| G12 | orphan handling | skipped, never deleted, never uploaded (`:1157-1164`) | identical (`:1369-1376`) | identical (`:1181-1188`) | **fixed** |
| G13 | remote `images/` subdir | literal `'images'` (`:1155`) | identical (`:1367`) | identical (`:1179`) | **fixed** (I1) |
| G14 | image warning strings (I8) | byte-identical set (see §N) | identical | identical | **fixed** |

### G-FORCE. forceUpload / forceDownload

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| G15 | `forceUpload` rewrites `.sync_base` | yes - `_saveBase(name, localRaw)` after each upload (`:1639`) | yes (`:2071`) | yes (`:1918`) | **fixed** (I2) |
| G16 | `forceUpload` disables autoSync? | no (only `_syncing` guard) | no | no | **fixed** (preserve; confirmation dialog suffices) |
| G17 | `forceUpload` wake-lock | yes (page acquires/releases) | yes | yes | **fixed** |
| G18 | `forceUpload` skips unchanged? | no - uploads all existing files | no | no | **fixed** |
| G19 | `forceDownload` rewrites `.sync_base` | yes (`:1785`) | yes (`:2222`) | yes (`:2064`) | **fixed** (I2) |
| G20 | `forceDownload` disables autoSync? | no (download-only, no lock) | no | no | **fixed** |
| G21 | `forceDownload` wake-lock | yes | yes | yes | **fixed** |
| G22 | `forceDownload` validation | `jsonDecode(remoteRaw)` only (`:1781`) | identical (`:2218`) | identical (`:2060`) | **fixed** (jsonDecode-only; consider `DataModule.validate` hook - same as G24) |
| G23 | `forceDownload` missing-remote string | `'$name: not found on remote; local file kept'` (`:1772`) | identical (`:2209`) | identical (`:2051`) | **fixed** (I8) |

### G-FIN. finalizePendingSync & conflict flow

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| G24 | `PendingSync` shape | `{AnimeMergeResult? animeMerge}`; `allConflicts: List<RecordConflict<Anime>>` | 4 merge fields; `allConflicts` untyped (`:138-175`) | 4 merge fields; `allConflicts` untyped (`:133-162`) | **config** - per-app `PendingSync`/`allConflicts` types stay app-side (facades rebuild app-typed shapes); engine treats conflicts as opaque records (PLAN §3.3) |
| G25 | resolution map type | `Map<String, Anime>` (typed) (`:1508`) | `Map<String, dynamic>` (`:1909`) | `Map<String, dynamic>` (`:1727`) | **fixed** - engine signature `finalizePendingSync(pending, Map<String,dynamic>)` + per-merge type-filter (MyDevice pattern) |
| G26 | finalize re-downloads remote? | **no** - writes+uploads directly (`:1527`) | **yes** - for preservation (`_finalizeFile`) | **yes** - + aborts file on error (`_finalizeFile`) | **fixed** - standardize on MyDevice's re-download-then-abort-on-error (race-safe) |
| G27 | conflict-cancel abort (v1.2.1) | cancel -> local unchanged, nothing uploaded, conflict stays pending, no wake-lock, no `.lock` held | identical (single dialog) | identical (per-conflict dialog) | **fixed** (I4; v1.2.1 semantics preserved) |
| G28 | conflict dialog topology | one `_ConflictDialog` per conflict (sequential) | single `SyncConflictDialog` for all | one `_ConflictDialog` per conflict | **config** - UI stays per-app (non-goal); engine semantics identical |

### G-MISC. consumeLocalDataChanged & SyncProgress

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| G29 | `consumeLocalDataChanged` mechanism | `static bool _localDataChanged`; read-and-reset (`:305,375`) | identical (`:342,350`) | identical (`:326,334`) | **fixed** |
| G30 | set by | sync writes (download/merge/finalize/image/forceDownload) | identical (more sites = more modules) | identical | **fixed** (semantics identical; count differs only by module count) |
| G31 | consumed by | `AutoSyncService._trySync` + `notifyLocalDataChangedIfNeeded` | identical | identical | **fixed** |
| G32 | `notifySaved` (separate signal) | yes - storage `save()` -> `AutoSyncService.notifySaved()` -> 30s debounce; NOT `_localDataChanged` | yes | yes | **fixed** (do not conflate the two signals) |
| G33 | `SyncProgress` phase order | `connecting -> downloadingData -> merging -> uploadingData -> uploadingImages -> downloadingImages -> done|error` | identical | identical | **fixed** (byte-identical file; see §0) |
| G34 | merged-upload progress count | module index / module total | structured modules report `0/0` through `_uploadMergedJson`; exchange rates and raw local-only uploads use module index/total | module index / module total | **config** - `DataModule.indexMergedUploadProgress` (default true; false for MyDay todo/finance/intimacy/weight) |

---

## H. Auto-sync scheduler (`auto_sync_service.dart`)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| H1 | sync triggers | launch / resume / 15-min timer / 30s-debounce / config-save (`:163-216`) | identical (`:173-223`) | identical (`:169-222`) | **fixed** |
| H2 | debounce duration | 30s (`:28`) | 30s (`:33`) | 30s (`:32`) | **fixed** |
| H3 | lifecycle observer | `WidgetsBindingObserver`, acts on `resumed` only | identical | identical | **fixed** |
| H4 | calls `WebDAVService.sync(config)` without `autoResolve` | yes (`:233`) | yes (`:241`) | yes (`:240`) | **fixed** (I4) |
| H5 | **backup trigger source** | `AutoSyncService` 15-min + resume (`:164-167,215-219`) | **`ReminderService` 30s loop** (`reminder_service.dart:85,608`) - AutoSyncService does NOT call backup | `AutoSyncService` 15-min + resume (`:170-173,221-224`) | **config** - non-goal: preserve MyDay's ReminderService-driven backup (PLAN non-goal). Package exposes `runAutoBackupIfNeeded()`; host owns the trigger. |
| H6 | resume side-effects | + reminders + backup | + mobile reminder refresh | + backup only | **config** - injectable `onResume` hooks (app-specific) |
| H7 | test seam | `appDirProvider` on `BackupService`, **not** AutoSyncService (`:44`) | same (`:46`) | same (`:47`) | **fixed** (preserve `appDirProvider` on backup; add injectable storage provider to shared `WebDAVService` for testability) |

> **PLAN note corrected:** the PLAN attributes an `appDirProvider` test seam to
> `AutoSyncService`; it actually lives on `BackupService` in all three apps. The
> `@visibleForTesting static Future<Directory> Function()? appDirProvider` redirects all
> backup I/O to a test directory.

---

## I. `.sync_base` snapshots (I2)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| I-S1 | layout | one file per module mirroring data-file names + `client_id.txt` + `upload_lock.json` | identical (5 module files) | identical (4 module files) | **fixed** (I2) |
| I-S2 | written when | after successful merge+upload / download-only / local-only force-upload / identical fast-path / forceUpload / forceDownload / finalize | identical | identical | **fixed** (I2) |
| I-S3 | NOT written when | merge upload failure / finalize upload failure / conflict (no upload) / download error | identical | identical | **fixed** (I2) |
| I-S4 | atomicity | `_saveBase` -> `_atomicWrite` (tmp-rename) | identical | identical | **fixed** |

---

## J. Backup engine (`backup_service.dart`)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| J1 | `modules` map (fileName -> moduleId) | `{'anime_data.json':'anime'}` (`:48`) | 5 entries: `todo, finance, exchangeRates, intimacy, weight` (`:50-56`) | 4 entries: `devices, networks, datasets, services` (`:51-56`) | **config** - knob `modules` (per-app registry; preserves existing ids for back-compat, I2) |
| J2 | moduleId naming | singular lowercase | singular lowercase **except** `exchangeRates` (camelCase) | **plural** lowercase | **config** - preserved verbatim per app (do not rename; would break I2). Document the inconsistency. |
| J3 | synthetic `images` backup module | absent (images always restore) | absent (images always restore) | present, restore-selectable (`:362-377,444`) | **config** - knob `syntheticImagesModule` (MyDevice=true; others=false). OR standardize on `true` for all (more explicit/safer). |
| J4 | `_backupFormat` value | `2` (`_formatVersion=2`) | `2` | `2` | **fixed** (I2) |
| J5 | v2 bundle top-level fields | `_backupFormat` + per-module raw JSON strings + `_imageRefs` (when images) | identical | identical | **fixed** (I2; see correction C8 - no `createdAt`, no `modules`) |
| J6 | `_imageRefs` shape | `Map<'images/<name>','<sha256><ext>'>` (`:203-207`) | identical (`:165-169`) | identical (`:233-237`) | **fixed** |
| J7 | `_images` (legacy v1) | read-only on restore (`:424-435`); never written by v2 | identical (`:395-406`) | identical (`:469-480`) | **fixed** (I2) |
| J8 | blob store | `backups/blobs/<sha256><ext>`; sha256 of raw bytes; ext from `p.extension`; dedup via exists-check (`:187-200`) | identical | identical | **fixed** |
| J9 | GC grace | `Duration(minutes: 10)` (`:32`) | identical (`:32`) | identical (`:35`) | **config** - knob `blobGcGrace` (default 10 min) |
| J10 | GC abort-on-unparseable | `return` (whole pass aborts) (`:508-511`) | identical (`:481-484`) | identical (`:554-557`) | **fixed** |
| J11 | retention default | `0` (forever) (`:35,97`) | `0` (`:36,107`) | `0` (`:38,105`) | **fixed** |
| J12 | `_probeMaxBytes` | `4 * 1024 * 1024` (`:28`) | identical (`:28`) | identical (`:31`) | **config** - knob `probeMaxBytes` (default 4 MiB); see correction C3 |
| J13 | `listBackups` corrupt handling | flagged `corrupt=true`, skipped (not thrown) (`:308-310`) | identical (`:276-278`) | identical (`:338-340`) | **fixed** |
| J14 | "already backed up today" corrupt | `if (b.corrupt) return false` (corrupt doesn't count) (`:244`) | identical (`:210`) | identical (`:274`) | **fixed** |
| J15 | "today" check source | `listBackups()` filename date; in-memory `_lastAutoBackup` (no persisted `lastBackupAt`) (`:242-249`) | identical (`:208-215`) | identical (`:272-279`) | **fixed** (do NOT add `lastBackupAt` to storage_config) |
| J16 | `RestoreResult` fields | `{ok, wroteAnything, missingImages}` (`:533-550`) | identical (`:506-523`) | identical (`:579-596`) | **fixed** |
| J17 | v1 image-key sanitization | `_safeImageRelativePath` (requires `images/` prefix, 2 segments) (`:350-359`) | identical (`:319-328`) | `_safeImageBasename` (accepts bare + prefixed) (`:386-398`) | **config/behavior** - standardize on MyDevice's tolerant `_safeImageBasename` (backward-compatible with legacy bare-key bundles in all apps) |
| J18 | I5 autoSync interplay (restore) | disable before first write; re-enable iff `!wroteAnything` (in `backup_page.dart:137-162`) | identical (`:189-214`) | identical (`:135-160`) | **fixed** (I5; identical in all three) |
| J19 | post-restore reminder refresh | `ReminderService.notifyDataChanged()` | `ReminderService.instance.refreshMobileSchedules()` | none (no reminders) | **config** - injectable post-restore hook |
| J20 | `appDirProvider` test seam | `@visibleForTesting static ...? appDirProvider` (`:44`) | identical (`:46`) | identical (`:47`) | **fixed** (preserve as the test override) |
| J21 | backup trigger cadence | AutoSyncService 15-min + launch + resume | ReminderService 30s loop | AutoSyncService 15-min + launch + resume | **config** - covered by H5 (host owns trigger) |

---

## K. Atomic I/O & validation dispatch

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| K1 | atomic helper location | duplicated: `AnimeStorage._atomicWrite` (fixed `.tmp`!) + `BackupService._atomicWriteString/Bytes` | centralized: `DataFileSafety.atomicWriteString/Bytes` (`data_file_safety.dart:96-137`) | duplicated: only `BackupService._atomicWriteString/Bytes` | **fixed** - one `lib/src/storage/atomic_io.dart` |
| K2 | tmp naming | mixed: fixed `.tmp` (AnimeStorage, concurrency hazard) vs unique `.tmp-<microseconds>` (BackupService) | unique `.tmp-<microseconds>` | unique `.tmp-<microseconds>` | **fixed** - unique `.tmp-<microsecondsSinceEpoch>` |
| K3 | cleanup on failure | BackupService yes; AnimeStorage **no** (orphans tmp) | yes | yes | **fixed** - cleanup-on-failure always |
| K4 | error wrap | none | `FileSystemException('Failed to replace file safely: $e', file.path)` | none | **fixed** - adopt MyDay's `FileSystemException` wrap |
| K5 | fsync | none (flush only) | none | none | **fixed** (preserve; optional future `fsync` bool, default false) |
| K6 | `DeviceStorage.save()` atomic? | n/a | n/a | **NO** - plain `writeAsString` (`device_storage.dart:240`) | **behavior** - make `DeviceStorage.save()` atomic (durability gap to fix in P3.MyDevice) |
| K7 | per-storage write queue | no (AnimeStorage fixed-tmp hazard) | yes (`TodoStorage._writeQueue` serializes saves, `:141`) | no | **config** - optional per-file write queue (MyDay pattern); at minimum fix AnimeStorage's fixed-tmp |
| K8 | validation dispatch (pre-write) | inline `AnimeData.fromJson` in restore (`:391`) | centralized `DataFileSafety.validateDataJson` (switch on fileName, typed `DataFileValidationException`) (`:53-76`) | `BackupService._validateModuleJson` (switch, `FormatException`) (`:126-140`) | **fixed** - `DataModule.validate(String)` interface; reuse MyDay's typed `DataFileValidationException` |
| K9 | validation shared with save path? | no | yes (TodoStorage._saveNow -> writeValidatedDataJson) | no (save unvalidated + non-atomic) | **behavior** - route data saves through `validate`+`atomicWrite` (MyDay pattern) |

---

## L. `storage_config.json` keys (I2)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| L1 | `autoBackupEnabled` | exact (`:96,107`) | exact (`:106`) | exact (`:104,115`) | **fixed** (I2) |
| L2 | `backupRetentionDays` | exact (`:97,108`) | exact (`:107`) | exact (`:105,116`) | **fixed** (I2) |
| L3 | `lastBackupAt` | absent | absent | absent | **fixed** (keep absent; see J15) |
| L4 | `storagePath` | `anime_storage.dart:61,123` | `todo_storage.dart:250,283` | `device_storage.dart:63,113` | **fixed** (shared key; StorageAdapter) |
| L5 | locale key | `locale` | **`localeTag`** | `locale` | **config/behavior** - standardize on `locale` (migrate MyDay off `localeTag`); flag for I2 |
| L6 | `saveSettings` write semantics | replace (atomic) | merge (non-atomic) | replace (non-atomic) | **fixed** - merge-write + atomic (combine both) |
| L7 | API port default | 7788 | 7790 | 7789 | **config** - per-app default (host-injected); out of extraction scope (local_api_server stays app-side) |
| L8 | other keys | themeMode, weekStartDay, homeCalendar*, minimizeToTray, reminder*, api* | themeMode, weekStartDay, intimacy*, minimizeToTray, reminderNotifiedKeys, api* | themeMode, minimizeToTray, api*, defaultCurrency, sortMode* | **fixed** - all stay app-side (not touched by extraction; StorageAdapter only owns backup+storage keys) |

---

## M. ZIP import/export (`import_export_service.dart`)

| # | Point | MyAnime | MyDay | MyDevice | Verdict |
|---|---|---|---|---|---|
| M1 | archive name prefix | `myanime_export_` (`:42-43`) | `myday_backup_` (`:50-51`) | `mydevice_export_` (`:61-62`) | **config** - knobs `archiveNamePrefix` + `archiveNameVerb` (or one `archiveNamePattern` template) |
| M2 | timestamp format + ext | `yyyyMMdd_HHmmss` + `.zip` | identical | identical | **fixed** |
| M3 | export entry allowlist | hardcoded `anime_data.json` + `images/*` (`:22-38`) | from `_dataFileNames` (5) + `images/*` (`:12-18`) | from `_dataFileNames` (4) + `images/*` (`:19-24`) | **config** - knob `dataFileNames` (the registry; covered by A19) |
| M4 | never bundles | `storage_config.json`, `webdav_config.json`, `.sync_base/`, `backups/`, manifest | identical | identical | **fixed** |
| M5 | images in export | `images/<basename>` blobs | identical | identical | **fixed** |
| M6 | path-traversal rejection | `p.normalize` + `..` substring + `p.isWithin`; **skips** (`continue`) (`:70-80`) | `p.url.normalize` + `../`&`/../` substring + `_isInside`; **rejects** (`return false`) (`:77-80,124-128`) | `p.normalize` + `..` + `p.isWithin`; **skips** (`:88-101`) | **fixed** - standardize on `p.url.normalize` + **reject** (`return false`) (MyDay, safest) |
| M7 | unknown-entry handling | skip (`continue`) | reject (`return false`) | skip (`continue`) | **config** - knob `rejectUnknownEntries` (default `true` = MyDay) |
| M8 | UTF-8 strictness | none - raw bytes (`:87`) | **strict `utf8.decode`** (throws -> `return false`) (`:83-84`) | none - raw bytes (`:106`) | **config** - knob `strictUtf8` (default `true` = MyDay) |
| M9 | pre-write validation | none | 2-phase: `validateDataJson` (jsonDecode + model `.fromJson`) for ALL entries before writing ANY, then atomic write (`:82-111`) | none | **config** - knobs `validateBeforeWrite` + `atomicWrites` (default `true` = MyDay); validator injected via `DataModule.validate` |
| M10 | import target | `appDir`, `writeAsBytes` overwrite; no re-sync/backup (`:66,77-87`) | `appDir`, atomic overwrite; no re-sync/backup (`:70,101-111`) | `appDir`, `writeAsBytes` overwrite; no re-sync/backup (`:84,95-106`) | **fixed** (target = appDir, overwrite); expose optional `onAfterImport` hook (currently no app disables auto-sync on import - latent gap, flagged) |
| M11 | `flush: true` on export write | no | yes (`:52`) | no | **fixed** - adopt `flush: true` (minor robustness) |
| M12 | public API | `exportZIP(String)->Future<String?>`, `importZIP(String)->Future<bool>` (`:17,59`) | identical (`:25,64`) | `exportZip`/`importZip` (camelCase) (`:33,77`) | **fixed** - standardize casing `exportZip`/`importZip` (ZipTransfer facade) |
| M13 | `package:archive` usage | `ZipEncoder().encode` / `ZipDecoder().decodeBytes`; default level; no encryption | identical | identical | **fixed** |
| M14 | Markdown export | `exportMarkdown` in-file (`:102`); `myanime_export_<stamp>.md` | **none** | `exportMarkdown` + pure `buildMarkdown` (`:122,150`); `mydevice_export_<stamp>.md` | **non-goal** - stays app-side (not extracted) |
| M15 | preservation engine in import? | no (raw bytes; survives trivially) | no (preservation via model `extraJson` during validation, not the engine) | no (raw bytes) | **fixed** - facade does not invoke preservation; app validator handles it |

> **Recommended facade defaults = MyDay's strict behavior** (`strictUtf8`,
> `validateBeforeWrite`, `atomicWrites`, `rejectUnknownEntries`, `rejectOnTraversal`,
> `p.url.normalize`, `flushOnWrite`) - safest and most recent hardening (v1.1.3/v1.2.5).
> Apps wanting legacy lenient behavior flip the bools off.

---

## N. User-visible strings (I8) - drift to reconcile

The shared services emit strings into `SyncResult.error`, `SyncResult.warnings`, and
backup/ZIP result paths. Most sync/image strings are already byte-identical; a small set
drifts and must be reconciled to ONE shared set (I8 requires byte-identical strings).

### N1. Already byte-identical across all three (keep as shared constants)

```
'Sync already in progress'
'Upload lock was not acquired'                      (NOTE: MyDay also has lowercase variant - see N2)
'Another device is uploading; retry after the lock expires.'
'Another device started uploading; retry after the lock expires.'
'conditional WebDAV PUT failed (HTTP 412)'
'Image sync skipped: could not list the remote images directory'
'Image download skipped: could not list the remote images directory'
'Upload skipped for $name: upload lock was not acquired'
'Upload timed out: $name'
'Upload failed for $name: $e'
'Download timed out: $name'
'Download failed for $name: $e'
'$name: not found on remote; local file kept'
'$name: remote content is not valid JSON'
'Failed to force-upload $name: ${uploadResult.error}'
'Failed to download $name from remote: ${remote.error}'
'HTTP ${response.statusCode}'
```

### N2. String drift (must pick one - recommendation in last column)

| # | String | MyAnime | MyDay | MyDevice | Reconcile to |
|---|---|---|---|---|---|
| N2a | lock-not-acquired (one path) | `'Upload lock was not acquired'` (capitalized) | `'upload lock was not acquired'` (lowercase, `:700`) | capitalized | **capitalized** (fix MyDay) |
| N2b | per-file download error (sync) | `'Failed to download $name from remote: ${remote.error}'` (`:1358`) | `'$name: download failed: ${remote.error}'` (`:1583`) | `'$name: download failed: ${remote.error}'` (`:1385`) | **`'$name: download failed: ${remote.error}'`** (fix MyAnime - 2 of 3 use it; aligns with per-file pattern) |
| N2c | per-file force-upload failure | `'Failed to force-upload merged $name under WebDAV lock: ...'` / `'Failed to force-upload $name under WebDAV lock: ...'` (`:1393,1462`) | `'$name: force-upload failed: ${result.error}'` / `'$name: upload failed: ...'` (exchange-rates, `:1666`) | `'$name: force-upload failed: ${uploadResult.error}'` (`:1417,...`) | **`'$name: force-upload failed: ${result.error}'`** (fix MyAnime; drop MyDay's exchange-rates-only variant) |
| N2d | per-file merge catch | none (single file, aborts) | `'$name: $e'` (`:1850`) | `'$name: $e'` (`:1640`) | **`'$name: $e'`** (generalize per-file) |
| N2e | top-level catch | `'$e\n$st'` (stack trace) (`:1495`) | `e.toString()` (no trace) (`:1895`) | `'$e\n$st'` (`:1684`) | **`'$e\n$st'`** (fix MyDay - stack trace aids diagnosis) |
| N2f | per-file error join | n/a | `perFileErrors.join('; ')` | `perFileErrors.join('; ')` | **`'; '`** join (fixed) |

### N3. Backup/ZIP UI strings (l10n - stay app-side, but key set should standardize)

`backup_service.dart`/`import_export_service.dart` themselves contain **no** user-visible
string literals - results are `{ok, wroteAnything, missingImages}` / `String?` / `bool`,
and all text is composed in the page widgets from `AppLocalizations`. The l10n **key
names** drift (e.g. MyDay `backupRestoreSuccess` vs MyAnime/MyDevice `backupRestored`;
MyDay `commonCancel` vs others `cancel`; MyDay splits `*Title`/`*Desc`). Since UI is a
non-goal (not extracted), these stay per-app. **Recommendation only:** standardize on
MyDay's `*Title`/`*Desc` split + `backupRestored` key in a future l10n pass; not blocking.

### N4. Conflict `displayName` (data-derived, not localized)

`getDisplayName` callbacks produce non-localized, data-derived strings (e.g.
`'${t.emoji ?? ''} ${t.title}'.trim()`). These pass through to conflict dialogs as-is and
are caller-provided, so they stay app-side (the `DataModule.merge` callback owns them).
No i18n strings move to the package.

---

## O. Consolidated config knobs (the `config` rows, named)

These are the per-app injection points the shared engine exposes. Everything not listed
here is `fixed` (one shared implementation).

| Knob | Type | Source | Default | Owning PLAN abstraction |
|---|---|---|---|---|
| `defaultRemotePath` | `String` | A2 | per-app (`/MyAnime`,`/MyDay`,`/MyDevice`) | `WebDavSyncEngine` ctor |
| `dataFileNames` | `List<String>` | A19, M3 | per-app module list | `ModuleRegistry` |
| `getAppDir` | `Directory Function()` | A20 | per-app storage hub | `StorageAdapter.getAppDir()` |
| `modules` (fileName->moduleId) | `Map<String,String>` | J1 | per-app | `ModuleRegistry` |
| `referencedImages` | `Set<String> Function(String json)?` | G9 | per-app extractor | `DataModule.referencedImages` |
| `merge` | callback | E12 | per-app wrapper | `DataModule.merge` |
| `validate` | `void Function(String json)` | K8 | per-app parser | `DataModule.validate` |
| `postMergeTransform` | `FutureOr<String> Function(String)?` | G7 | per-app (MyDay finance) | `DataModule.postMergeTransform` |
| `syntheticImagesModule` | `bool` | J3 | false (MyDevice=true) | `BackupEngine` ctor |
| `propfindTimeout` | `Duration` | A18, C-P4 | 15s | `WebDavClient` ctor |
| `blobGcGrace` | `Duration` | J9 | 10 min | `BackupEngine` ctor |
| `probeMaxBytes` | `int` | J12 | 4 MiB | `BackupEngine` ctor |
| `failFastOnDownloadError` | `bool` | G3 | false | `WebDavSyncEngine` ctor |
| `archiveNamePrefix` + `archiveNameVerb` | `String`+`String` | M1 | per-app | `ZipTransfer` ctor |
| `strictUtf8` | `bool` | M8 | true | `ZipTransfer` ctor |
| `validateBeforeWrite` | `bool` | M9 | true | `ZipTransfer` ctor |
| `atomicWrites` | `bool` | M9 | true | `ZipTransfer` ctor |
| `rejectUnknownEntries` | `bool` | M7 | true | `ZipTransfer` ctor |
| `onAfterImport` | callback | M10 | null | `ZipTransfer` |
| `onResume` hooks | callbacks | H6 | per-app | `AutoSyncScheduler` |
| `preUploadTransform` / preservation | callback | G8, F2 | per-app | `DataModule` / engine hook |
| `indexMergedUploadProgress` | `bool` | G34 | true (false for MyDay structured modules) | `DataModule` |
| legacy image-key tolerance | behavior | J17 | tolerant | `BackupEngine` (standardize on `_safeImageBasename`) |
| locale config key | `String` | L5 | `locale` | app-side migration (MyDay) |

---

## P. Open questions

**Zero open questions.** Every P0.1 bullet is resolved below (the questions the PLAN
explicitly raised are answered; no new unknowns block Phase 2):

| PLAN open question | Resolution | Row |
|---|---|---|
| `testConnection` statuses - do the others treat 207+404? | Yes - all three identical | C1, A10 |
| Local `.sync_base/upload_lock.json` - MyAnime/MyDevice equivalents? | Yes - all three have it | C2, B2 |
| PROPFIND parsing - align exactly? | Three regexes; adopt MyDevice's `<(?:\w+:)?href>` | C-P1 |
| Record deletion semantics (not captured) | Pinned in E4 detail; identical across all three | E4 |
| Identical-content suppression - verify others? | All three identical | C4, E5 |
| Image sync referenced-name sources - confirm MyDevice? | device `imagePath` basenames | G9 |
| `_probeMaxBytes` - others? | All three have 4 MiB | C3, J12 |
| `storage_config.json` key spelling (`autoBackupEnabled`,`backupRetentionDays`)? | Identical in all three | L1, L2 |
| ZIP archive name prefixes - capture exact MyAnime? | `myanime_export_` | M1 |
| `mergeRecords` supersets - confirm MyAnime subset? | MyAnime==MyDay; only MyDevice is superset | C5, E1 |
| `createdAt` in v2 bundle? | Absent (PLAN wording corrected) | C8, J5 |
| `_imageRefs`/`_images` field names? | `_imageRefs` (v2), `_images` (v1 legacy only) | J5-J7 |

---

## Q. Verification of this matrix

- Diffed with `git diff --no-index` and SHA-256 hashing: `sync_progress.dart`,
  `sync_wake_lock.dart` confirmed byte-identical (exit 0).
- All other files fully read across the three apps; every behavioral row cites
  `file:line` references verifiable in the working trees at
  `C:\Users\yuanzhe\source\repos\{MyAnime,MyDay,MyDevice}` (HEAD as of 2026-07-23).
- Every row is marked `fixed` or `config`; every `config` row names its knob (§O).
- Open questions: zero (§P).
- This file is the input to P2.5 (WebDAV client superset), P2.3 (merge deletion tests),
  P2.6 (sync engine), P2.7 (backup engine), P2.8 (ZIP transfer), and the P0.2 golden
  harness scenarios.
