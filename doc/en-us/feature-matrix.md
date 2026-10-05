# Shared behavior and configuration

This page describes reusable engine contracts. Application module selections,
adapter implementations and integration history belong in application repositories.
See [invariants.md](invariants.md) for compatibility rules and
[functions/INDEX.md](functions/INDEX.md) for full API documentation. Section labels
retain the reference identifiers used by the API pages.

## A. WebDAV configuration and transport

Applications supply remote paths and credentials. The transport provides URL
normalization, Basic authentication and injectable request timeouts. Connection
checks accept 207 and 404. Configuration round trips preserve unknown keys.

## B. Upload locks

Remote `.lock` and local `.sync_base/upload_lock.json` state coordinate uploads.
Defaults are a 60-second TTL and 20-second heartbeat. Conditional lock writes use
ETags and do not retry; callers retain ownership and stale-lock checks.

## C. Directory parsing

PROPFIND parsing accepts namespaced and unprefixed href elements with
`<(?:\w+:)?href>`. Failure remains distinguishable from an empty listing.

## D. Retry policy

Transient failures and server errors receive at most two extra attempts with
1-second and 2-second backoff. Client errors and lock writes do not retry.

## E. Record merge

The generic three-way merge accepts domain callbacks and optional unknown-field
preservation. Identical serialized content suppresses unnecessary conflicts.
Domain-specific composite-key merges remain application-owned.

### E4. Record deletion semantics

| Scenario | Result | Conflict? |
|---|---|---|
| Deleted locally, remote unchanged in base | Excluded | No |
| Deleted locally, remote modified | Remote kept | No |
| Deleted remotely, local unchanged in base | Excluded | No |
| Deleted remotely, local modified | Local kept | No |
| Deleted both sides | Excluded | No |
| Added on one side without base | Included | No |
| Both added same ID without base | Latest modifiedAt; ties choose remote | No |

Modify wins over delete. Shared merge tests pin these semantics.

## F. Unknown JSON fields

Both schema-driven recursive preservation and flat unknown-field merging are
available. Applications supply schemas or model callbacks and decide whether
preservation occurs during merge or before upload.

## G. Sync orchestration

The ordered module registry supplies files, validation, merge, referenced images
and transforms. Sync maintains base snapshots, explicit pending conflicts and a
sticky local-change signal. Finalization re-downloads remote data before upload.
Download errors are collected per file by default; fail-fast is configurable.
Images synchronize additively and only when referenced. Module callbacks own
display names, JSON formatting and determinate upload progress selection.

## H. Auto-sync scheduling

The scheduler handles start, resume, periodic and debounced-save triggers with an
in-flight guard. Start, resume and periodic sync cancel pending save debounce.
Applications supply resume and periodic hooks, reload behavior and backup triggers.

## I. Base snapshots

Preserve `.sync_base` formats and UTC timestamps. Unknown JSON fields survive
parse, merge and write. Paths and module contents remain application-owned.

## J. Backup

V2 bundles store raw module JSON and `_imageRefs`; legacy v1 uses `_images`.
Content-addressed blobs use reference-counted garbage collection, a default
10-minute grace and abort-on-unparseable behavior. Retention and daily backup
guards remain configurable. Restore validates selected modules before writing and
disables auto-sync before its first write. Optional synthetic `images` selection
controls image restore. Image keys accept bare names and `images/<name>`, while
rejecting nested, absolute and traversal paths. Probe limit defaults to 4 MiB.

## K. Atomic I/O and validation

Same-directory temporary files support validated atomic replacement. Optional
per-owner queues serialize writes without globally serializing unrelated files.
`DataModule.validate` supplies domain validation and typed file errors.

## L. Storage settings

Preserve `storage_config.json` keys including `autoBackupEnabled` and
`backupRetentionDays`. Daily backup does not persist a `lastBackupAt` key.
Application-specific settings migrations remain outside the package.

## M. ZIP transfer

Exports use registry files and flat `images/<basename>` entries. Import rejects
traversal and classifies entries before writing. Unknown-entry rejection, strict
UTF-8 decoding, validation before write and atomic writes default to true.
Archive naming and after-import actions are application-supplied.

## N. User-visible text

Keep shared engine errors compatible, subject to the accepted changes in
[invariants.md](invariants.md). Localized UI labels and data-derived conflict names
remain application-owned.

## O. Configuration boundaries

Applications inject storage roots, module registries, remote paths, domain merge
and validation callbacks, image references, transforms, archive naming and lifecycle
hooks. Transport timeouts, backup retention, blob grace, probe size and import
strictness have explicit defaults. Consult the per-file API pages for signatures.

## P. Integration documentation

Record selected modules, persistence adapters, domain policies and regression
results in the application's documentation. The library imposes no consumer list.

## Q. Verification

Unit tests and package-owned synthetic registry goldens verify engine behavior,
requests and formats. Validate wire compatibility and application regressions
before changing shared contracts.
