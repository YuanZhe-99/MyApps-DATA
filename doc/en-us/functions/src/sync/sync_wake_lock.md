# lib/src/sync/sync_wake_lock.dart

Best-effort screen wake-lock ownership for foreground sync operations. P2.1 moved this file
verbatim after SHA-256 and `git diff --no-index` confirmed that all three app copies were
byte-identical.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `SyncWakeLock` | class | A | Coordinates shared foreground-sync wake-lock ownership. |
| `SyncWakeLock._()` | private constructor | A | Prevents instantiation of the static-only helper. |
| `SyncWakeLock.acquire()` | static method | A | Acquires one reference and enables the platform lock when needed. |
| `SyncWakeLock.release()` | static method | A | Releases one reference and disables only a sync-owned platform lock. |

## Behavior

### Ownership and reference counting

`SyncWakeLock` maintains a private reference count and an `enabledBySync` ownership flag.

1. The first `acquire()` asks `WakelockPlus.enabled` whether another feature already owns the
   platform lock.
2. If the lock is off, sync enables it and records ownership.
3. Overlapping foreground operations only increment the reference count; they do not issue extra
   platform enable calls.
4. `release()` disables the platform lock only when the final reference is released and sync was
   the feature that enabled it.
5. Releasing with a zero reference count is a safe no-op.

This ownership rule prevents sync completion from turning off a lock held by another feature, such
as MyDay's intimacy timer.

### `acquire()`

- **Inputs:** None.
- **Returns:** A future that completes after the best-effort platform state check/update.
- **Side effects:** Increments the reference count and may enable `wakelock_plus`.
- **Notes:** Foreground operations pair this call with `release()` in `finally`. Background
  auto-sync must not use it.

### `release()`

- **Inputs:** None.
- **Returns:** A future that completes after any required platform disable.
- **Side effects:** Decrements the reference count and may disable a sync-owned lock.
- **Notes:** Platform exceptions are swallowed by both methods so wake-lock failure cannot break
  data synchronization.
