# lib/src/data/zip_transfer.dart

Generic ZIP data transfer engine (P2.8), reconciled from the three apps'
`import_export_service.dart` implementations (feature-matrix §M). Export bundles exactly the
registry's data files plus flat `images/<basename>` entries; import is standardized on MyDay's
strict semantics with per-app leniency preserved as constructor knobs. Markdown export stays
app-side (M14, non-goal).

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `ZipClock` | typedef | A | Supply the current local time; injectable for tests. |
| `ZipAfterImportHook` | typedef | A | Optional app hook after a successful import (M10). |
| `ZipTransfer` | class | A | Registry-driven ZIP export/import. |
| `ZipTransfer` | constructor | A | Bind storage, registry, name prefix, and M-knobs. |
| `ZipTransfer._formatStamp` | private static method | A | Format `yyyyMMdd_HHmmss` without `intl` (M2). |
| `ZipTransfer._isInside` | private static method | A | Containment check behind the allowlist (M6). |
| `ZipTransfer.exportZip` | method | A | Write a timestamped archive of data files and images. |
| `ZipTransfer.importZip` | method | A | Two-phase validated import of allowlisted entries. |
| `ZipTransfer._writeBytes` | private method | A | Atomic or plain entry write (M9). |

## Export

`exportZip(destDir)` adds each existing registry data file in registry order, then every file in
`images/` as `images/<basename>` (M3/M5), encodes with `package:archive` defaults (M13), and
writes `<archiveNamePrefix><yyyyMMdd_HHmmss>.zip` with `flush: true` (M1/M2/M11). The prefix knob
preserves `myanime_export_`, `myday_backup_`, and `mydevice_export_`. Configuration,
`.sync_base/`, and `backups/` are never bundled (M4). Failure returns null.

## Import

`importZip(filePath)` is two-phase: every entry is classified (and, when enabled, validated)
before any file is written, so a rejected archive never leaves partial writes. Semantics are
MyDay's strict form by default:

- Traversal (`../`, `/../` after `p.url.normalize`) always fails the import (M6, fixed).
- Unknown entries and malformed image entries fail (true) or are skipped (false) via
  `rejectUnknownEntries` (M7; MyAnime/MyDevice use false).
- Data payloads are strict-UTF-8 decoded (true) or written raw (false) via `strictUtf8` (M8).
- `validateBeforeWrite` runs `DataModule.validate` on every data entry before any write (M9,
  true = MyDay); `atomicWrites` selects tmp-then-rename vs plain `writeAsBytes` (M9).
- Import overwrites inside the app directory only, never triggers re-sync or backup, and runs the
  optional `onAfterImport` hook once after success (M10). No preservation engine is invoked
  (M15); app validators handle preserved fields.
