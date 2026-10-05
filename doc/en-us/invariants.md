# Behavior contract: hard invariants

These are the rules the shared package must not break. They were the acceptance criteria for the
original extraction, and they remain the compatibility contract for applications
using this package — a violation here can strand installs already in the field.

Originally the "hard invariants" table of the one-off extraction plan, which has since been retired.
This content lives here because it is the behavior contract, not project-management history.

| # | Invariant |
|---|---|
| I1 | Remote WebDAV layout unchanged: same data file names, `images/` subdir, `.lock` file name and JSON schema. An **old app build and a new build syncing against the same server must interoperate**. |
| I2 | Local formats unchanged: `webdav_config.json`, `.sync_base/*` (incl. `upload_lock.json`), `backups/backup_*.json` (v2 written, v1 restorable), `backups/blobs/`, `storage_config.json` keys. |
| I3 | Lock semantics: 60 s TTL, 20 s heartbeat, stale-lock takeover rules, no retry on lock writes. Retry: max 2 extra attempts, 1 s/2 s backoff, transient + 5xx only, never 4xx. |
| I4 | Conflicts are never silently auto-resolved (`autoResolve: false` at every call site, manual and auto-sync alike). |
| I5 | Restore disables auto-sync in `webdav_config.json` before the first write; re-enables only if `wroteAnything == false`. |
| I6 | UTC timestamps; pretty-printed JSON (`withIndent('  ')`); unknown JSON fields survive parse→merge→write round trips. |
| I7 | Each app's existing public service API (`WebDAVService`, `BackupService`, `ImportExportService`, `AutoSyncService` — static classes, incl. `@visibleForTesting appDirProvider`) is preserved via facades so **all existing app tests pass unmodified**. |
| I8 | User-visible strings (warnings, errors surfaced to UI) are byte-identical, except where an accepted unification below says otherwise. |
| I9 | All new/moved code carries the Function Explanation Layer doc-comment block; each app's AGENTS.md is updated in the same change set. |
| I10 | The real Gitea address never appears in any committed file. |

## Unification rule

Prefer consistent shared behavior for incidental differences rather than adding
per-application knobs to preserve drift. Knobs are permanent complexity in the
shared engine; incidental drift is not worth carrying.
Only preserve a difference when unifying would actually break the function.

Domain needs stay configurable: backup triggers, whole-file merge policies,
synthetic `images` modules and composite-key record merges.

The prohibition is on *silent* picks, not deliberate ones. Every accepted unification must be flagged
to the owner, recorded below with its behavioral consequence, and reflected in re-recorded goldens.

## Accepted unifications

| Change | Consequence |
|---|---|
| **N2c** — per-file upload error string | Use `'$name: force-upload failed: …'` consistently. This accepted wording change is an exception to I8. |
| **G3** — download-error handling | Collect per-file errors by default (`failFastOnDownloadError: false`); callers may explicitly request fail-fast behavior. |
| **Finalize re-download** | `finalizePendingSync` issues one `GET <data file>` before uploading. This adds a request and aborts if the remote is unreadable, preventing a resolution from overwriting an unreadable remote. |
| **ZIP traversal rejection** | Reject the entire archive containing a path-traversal entry (false, no writes), preventing partial application of a tampered archive. |
| **Resume debounce cancel** | Resume cancels pending save-debounce before syncing; the in-flight guard prevents overlapping synchronization. |

## Where the per-behavior detail lives

[`feature-matrix.md`](feature-matrix.md) describes shared behavior and configuration
boundaries. Read it before changing sync, backup or ZIP engines.
