# lib/src/webdav/sync_progress.dart

Shared, UI-neutral progress types for WebDAV sync, force upload, and force download operations.
P2.1 moved this file verbatim after SHA-256 and `git diff --no-index` confirmed that all three app
copies were byte-identical.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `SyncPhase` | enum | A | Defines the high-level operation phases. |
| `SyncProgress` | class | A | Stores one immutable progress snapshot. |
| `SyncProgress(...)` | constructor | A | Creates a snapshot with optional detail and item counts. |
| `SyncProgress.fraction` | getter | A | Returns clamped measurable progress or null when indeterminate. |
| `SyncProgress.isRunning` | getter | A | Distinguishes active phases from idle and terminal phases. |
| `SyncProgressListenable` | typedef | A | Exposes the read-only listenable type consumed by app UIs. |

## Behavior

### `SyncPhase`

The order is part of the characterization contract:

`idle`, `connecting`, `downloadingData`, `merging`, `uploadingData`, `uploadingImages`,
`downloadingImages`, `done`, `error`.

The service reports phases and raw file/image details only. Each app remains responsible for
mapping phases to localized user-visible text.

### `SyncProgress`

- **Inputs:** A required `phase`, optional raw `detail`, and optional `current`/`total` counts.
- **Returns:** An immutable snapshot suitable for a `ValueNotifier`.
- **Side effects:** None.
- **Notes:** Counts default to zero. A zero `total` means the phase is indeterminate.

`SyncProgress.idle` is the canonical resting snapshot.

### `fraction`

- **Returns:** `current / total` clamped to `0.0..1.0`, or null when `total <= 0`.
- **Usage:** Bind directly to `LinearProgressIndicator.value`.

### `isRunning`

- **Returns:** False for `idle`, `done`, and `error`; true for every other phase.
- **Notes:** `done` and `error` are terminal snapshots, not active operations.

### `SyncProgressListenable`

Alias for `ValueListenable<SyncProgress>`. Consumers listen without gaining mutation access to the
service's underlying `ValueNotifier`.
