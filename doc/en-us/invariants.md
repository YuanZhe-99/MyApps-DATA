# Behavior contract: hard invariants

These are the rules the shared package must not break. They were the acceptance criteria for the
original extraction, and they remain the compatibility contract now that three shipped apps depend on
this package — a violation here can strand installs already in the field.

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

When the three apps differ on something incidental and two of them already agree, **take the good
unification** — change the odd app out to match, rather than adding a per-app knob to preserve the
drift. Knobs are permanent complexity in the shared engine; incidental drift is not worth carrying.
Only preserve a difference when unifying would actually break the function.

Genuine per-app needs stay configurable: MyDay's `ReminderService`-driven backup, its whole-file
exchange-rate merge, MyDevice's synthetic `images` module and `mergeAssignments`.

The prohibition is on *silent* picks, not deliberate ones. Every accepted unification must be flagged
to the owner, recorded below with its behavioral consequence, and reflected in re-recorded goldens.

## Accepted unifications

| Change | Consequence |
|---|---|
| **N2c** — per-file upload error string | MyAnime adopted MyDay/MyDevice's `'$name: force-upload failed: …'`. A user-visible string changed, which is why I8 carries an exception. |
| **G3** — download-error handling | MyAnime moved from abort-whole-sync to per-file error collection (engine default `failFastOnDownloadError: false`). With one module the observable outcome is unchanged. |
| **Finalize re-download** | MyAnime's `finalizePendingSync` now issues one `GET <data file>` before uploading, matching MyDay/MyDevice. Costs one extra request per finalize and adds an abort-if-the-remote-is-unreadable guard — strictly safer, since it prevents uploading a resolution over a remote that just became unreadable. MyAnime's `sync_conflict_finalize` golden was re-recorded; the diff is exactly that one inserted GET. |
| **ZIP traversal rejection** | An archive containing a path-traversal entry is now rejected outright (import returns false, nothing is written) instead of skipping the bad entry and importing the rest. MyAnime and MyDevice adopted MyDay's behavior. Nothing ever landed outside the app dir either way; the change is that a tampered archive can no longer be half-applied. |
| **Resume debounce cancel** | Resume cancels a pending save-debounce before syncing, instead of leaving it queued. MyDevice adopted MyAnime's behavior; the in-flight guard already made the difference unobservable. |

## Where the per-behavior detail lives

[`feature-matrix.md`](feature-matrix.md) is the historical three-way audit of the apps' original
implementations — every behavioral point, what each app did, and whether it became `fixed` or a
`config` knob. Read it before changing anything in the sync, backup, or ZIP engines.
