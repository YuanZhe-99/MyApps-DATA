# Golden (characterization) test harness

> PLAN task **P0.2**. Captures the **current** behavior of the three apps'
> WebDAV sync, backup, and ZIP services as machine-checkable **golden files**, so
> that after the shared `myapps_data` engine replaces the in-app copies (Phase 2
> / Phase 3), the *same scenarios reproduce the identical request sequences and
> on-disk formats* (invariants I1-I3). This is the behavioral contract for "zero
> functional change".

## What is here

This directory is the **canonical** home of the shared harness components:

| File | Role |
|---|---|
| `fake_webdav_server.dart` | `FakeWebDAVServer` - in-memory `http.BaseClient` WebDAV double: file map, strong-ETag / `If-Match` / `If-None-Match` lock preconditions (412), PROPFIND depth 0/1 listing, MKCOL, GET/PUT/DELETE, and fault injection (5xx / 404 / timeout / stale lock). |
| `request_recorder.dart` | `RequestRecorder` - wraps the server and logs every exchange (method, path, headers-that-matter, body). `GoldenTranscript` renders a **normalized** transcript (etags/uuids/timestamps/sha256/abs-paths -> placeholders). `GoldenMatcher` records or diffs goldens. |
| `harness_self_test.dart` | Self-test proving the server + recorder model the lock lifecycle, listing, and fault injection. |
| `spike_runwithclient_test.dart` | The original proof that `runWithClient` intercepts every HTTP path. |

The **per-app drivers + goldens live in each app repo** (they must import the app's
real, unmodified services):

```
<App>/test/golden/
  fake_webdav_server.dart     # COPIED from here (provenance header)
  request_recorder.dart       # COPIED from here (provenance header)
  webdav_golden_test.dart     # app-specific scenario driver (imports the app's services)
  goldens/<app>/*.txt         # recorded transcripts + format goldens
```

Phase 2 reuses this canonical copy in
`shared_engines_golden_test.dart` to run the new engines against synthetic
MyAnime/MyDay/MyDevice registries. Package-owned fixtures live under
`goldens/<app>/`. Phase 3 re-records against each integrated app and diffs.

## Why this design (P0.2 "implementer's choice")

P0.2 offered "copied sources or a small harness app". We chose an **in-app harness**
so the goldens are produced by the **real, unmodified app code** (the PLAN's "no app
source code modified" rule holds). Two seams make that possible with zero `lib/`
changes:

1. **HTTP interception** - `runWithClient(body, () => recorder)` (from
   `package:http/src/client.dart`). The `http` `Client()` factory resolves
   `zoneClient ?? createClient()`, so a zone-scoped factory intercepts **both** the
   inline `http.Client().send(...)` streaming calls (testConnection / PROPFIND /
   MKCOL) **and** the top-level `http.get/put/delete` calls (upload/download). No
   injection point exists in the app source, so the zone is the only way in.
   > Gotcha: `package:http/http.dart` exports `src/client.dart` with `hide zoneClient`
   > and, in this SDK, that export does **not** surface `runWithClient` to consumers -
   > import it directly from `package:http/src/client.dart` (test-only code).

2. **Directory isolation** - `PathProviderPlatform.instance = _FakePathProvider(tmp)`
   (the apps' existing test pattern). Each scenario gets a fresh temp dir; the storage
   hubs' `_getDefaultAppDir()` re-reads it every call, and since the harness never
   writes a `storagePath`, `_customPath` stays null and there is no cross-scenario
   static-cache leakage. `BackupService` uses its existing
   `@visibleForTesting appDirProvider`.

## Scenarios (per app)

Sync request-sequence goldens (`sync_*.txt`, `force_*.txt`):
first sync · no-change sync · local-only change · remote-only change ·
both-changed-identical · true conflict + finalize · force upload · force download ·
interrupted-upload recovery (leftover local lock) · image add on each side.

Backup goldens: v2 create bundle layout (`backup_v2_create.txt`) + corrupt-bundle
flag (behavioral assert).

ZIP goldens: export entry list (`zip_export_entries.txt`) + import rejection
(traversal: MyDay rejects→false; MyAnime/MyDevice skip→true, file never escapes appDir).

Every P0.1 `fixed` row that is observable over the wire has a scenario; per-app
`config` rows (module lists, image sources, ZIP strictness) show up as per-app
golden differences, which is exactly what we want to lock in.

## Re-run (one command per app)

From the app repo root:

```powershell
# Verify (fail on any behavioral drift):
flutter test test/golden/webdav_golden_test.dart

# Re-record goldens after an intentional behavior change:
flutter test --dart-define=GOLDEN_RECORD=true test/golden/webdav_golden_test.dart
```

Or run all three at once from the workspace root:

```powershell
foreach ($a in 'MyAnime','MyDay','MyDevice') {
  Set-Location "C:\Users\yuanzhe\source\repos\$a"
  flutter test test/golden/webdav_golden_test.dart
}
```

The canonical harness self-test:

```powershell
Set-Location C:\Users\yuanzhe\source\repos\MyApps-DATA
flutter test test/golden/
```

The P2.10 shared-engine replay, from the MyApps-DATA package root:

```powershell
# Verify all 36 package fixtures (CI default):
flutter test test/golden/shared_engines_golden_test.dart

# Re-record after an intentional engine/fixture change:
flutter test --dart-define=GOLDEN_RECORD=true test/golden/shared_engines_golden_test.dart
```

The package driver preserves the P0.2 scenario and request topology with the
real app registry order, filenames, remote paths, image-reference locations,
backup keys, and archive prefixes. Payload records are synthetic because app
models and merge wrappers intentionally stay app-side. Conflict finalization
also includes the shared engine's deliberate fresh remote GET before upload;
this race-safer P2.6 behavior differs from MyAnime's old transcript and is
recorded explicitly rather than hidden.

## Reading a golden

Each line is one HTTP exchange: `=== [i] METHOD /path -> status`, then the
headers-that-matter and the (normalized) body. Example (`sync_first.txt`):

```
=== [2] PUT /dav/files/u/MyAnime/.lock -> 201
  if-none-match: *
  body:
    { "clientId": "<uuid>", "token": "<uuid>", "startedAt": "<timestamp>", ... }
```

This shows the lock acquired with `If-None-Match: *` before any download, the lock
JSON schema, and normalized volatile values - the I1/I2/I3 proof.
