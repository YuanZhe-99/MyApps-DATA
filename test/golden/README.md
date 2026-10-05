# Golden test harness

Package-owned synthetic fixtures verify shared WebDAV request sequences, backup
formats and ZIP entry lists. Application integration drivers and their results
belong in the corresponding application repositories.

## Harness components

| File | Role |
|---|---|
| `fake_webdav_server.dart` | In-memory WebDAV client double with files, ETags, conditional locks, listings and fault injection |
| `request_recorder.dart` | Normalized request transcripts, recording and comparison |
| `harness_self_test.dart` | Lock, listing and fault-injection checks |
| `spike_runwithclient_test.dart` | HTTP interception checks |
| `shared_engines_golden_test.dart` | Shared engine driver for synthetic registry shapes |

Fixture directory names are stable test identifiers, not a supported consumer
list. Records are synthetic; application models and merge wrappers stay app-owned.

## Scenarios

Request fixtures cover first sync, no changes, local and remote changes, identical
changes, conflict finalization, force operations, interrupted-upload recovery and
image additions. Format fixtures cover backup v2 creation and ZIP export entries.
Behavior assertions cover corrupt bundles and traversal rejection. Finalization
includes a fresh remote GET before uploading a resolution.

## Verification

Run from the package root:

```bash
flutter test test/golden/
flutter test test/golden/shared_engines_golden_test.dart
```

Re-record only after an intentional behavior or fixture change:

```bash
flutter test --dart-define=GOLDEN_RECORD=true test/golden/shared_engines_golden_test.dart
```

Each transcript records method, path, relevant headers and normalized body.
Variable ETags, UUIDs, timestamps, hashes and absolute paths become placeholders.
Read fixture diffs alongside the compatibility rules in
[invariants.md](../../doc/en-us/invariants.md).
