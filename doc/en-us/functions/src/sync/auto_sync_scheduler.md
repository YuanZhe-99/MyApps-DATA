# lib/src/sync/auto_sync_scheduler.dart

Generic auto-sync scheduler core (P2.9), extracted from the three apps' `auto_sync_service.dart`
singletons (feature-matrix §H). The scheduler owns only the trigger topology, the `_syncing`
guard, in-memory status, and reload/status listener fan-out; the actual sync runs through the
app-provided `runSync` hook (typically delegating to `WebDavSyncEngine.sync`).

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `AutoSyncResult` | class | A | Report one sync attempt outcome for status recording. |
| `AutoSyncResult` | constructor | A | Create an immutable result. |
| `AutoSyncPredicate` | typedef | A | Return whether auto-sync is configured and enabled. |
| `AutoSyncRunSync` | typedef | A | Execute one sync attempt and report its outcome. |
| `AutoSyncConsumeLocalDataChanged` | typedef | A | Consume the engine local-data-changed flag. |
| `AutoSyncSideEffect` | typedef | A | Run an app-specific periodic/resume side effect. |
| `AutoSyncScheduler` | class | A | Lifecycle-observed, debounced, periodic auto-sync core. |
| `AutoSyncScheduler` | constructor | A | Bind hooks and fixed durations. |
| `AutoSyncScheduler.lastSuccessAt` | getter | A | Time of the last successful sync. |
| `AutoSyncScheduler.lastFailureAt` | getter | A | Time of the last failed sync. |
| `AutoSyncScheduler.lastError` | getter | A | Last sync error message. |
| `AutoSyncScheduler.hasPendingConflicts` | getter | A | Whether a conflict awaits manual resolution. |
| `AutoSyncScheduler.addOnLocalDataChanged` | method | A | Register a UI reload callback. |
| `AutoSyncScheduler.removeOnLocalDataChanged` | method | A | Unregister a UI reload callback. |
| `AutoSyncScheduler.addOnStatusChanged` | method | A | Register a status-change callback. |
| `AutoSyncScheduler.removeOnStatusChanged` | method | A | Unregister a status-change callback. |
| `AutoSyncScheduler.recordSyncResult` | method | A | Record a manual sync result. |
| `AutoSyncScheduler.recordFinalizeResult` | method | A | Record a conflict-finalization result. |
| `AutoSyncScheduler.notifyLocalDataChangedIfNeeded` | method | A | Fire reload listeners when the flag is set. |
| `AutoSyncScheduler.notifyLocalDataChangedNow` | method | A | Fire reload listeners unconditionally. |
| `AutoSyncScheduler.start` | method | A | Observe lifecycle, start timers, run first sync. |
| `AutoSyncScheduler.stop` | method | A | Cancel timers and remove the observer. |
| `AutoSyncScheduler.notifySaved` | method | A | Schedule a 30s trailing-edge debounced sync. |
| `AutoSyncScheduler.requestSyncNow` | method | A | Immediate sync, canceling any pending debounce. |
| `AutoSyncScheduler.didChangeAppLifecycleState` | method | A | Resume trigger plus app resume side effects. |
| `AutoSyncScheduler._requestSyncNow` | private method | A | Cancel debounce and kick off a guarded sync. |
| `AutoSyncScheduler._trySync` | private method | A | Run one guarded sync attempt and record status. |
| `AutoSyncScheduler._invokeSideEffect` | private method | A | Run an optional side-effect hook, swallowing errors. |
| `AutoSyncScheduler._recordSuccess` | private method | A | Record a successful sync. |
| `AutoSyncScheduler._recordFailure` | private method | A | Record a failed sync or pending conflicts. |
| `AutoSyncScheduler._fireLocalDataChanged` | private method | A | Invoke all reload listeners. |
| `AutoSyncScheduler._notifyStatusChanged` | private method | A | Invoke all status listeners. |

## Triggers (H1-H3)

The fixed trigger set is preserved: app launch (`start`), app resume (`resumed` only), a 15-minute
periodic timer, a 30-second trailing-edge debounce after `notifySaved`, and `requestSyncNow` after
enabling/saving auto-sync config. `notifySaved` is ignored before `start` so early storage writes
cannot schedule a sync. Launch, periodic, and resume are unified on canceling a pending
save-debounce before syncing immediately (MyAnime's behavior); `notifySaved` is the only
trailing-edge debounced trigger.

## Guard and status

`_trySync` silently skips when `_syncing` is already true (overlapping triggers are ignored, not
surfaced as errors). The config gate (`isAutoSyncActive`) runs before the guard is acquired, so a
not-configured attempt never blocks a later real sync. Outcomes are recorded in memory only
(`lastSuccessAt`/`lastFailureAt`/`lastError`/`hasPendingConflicts`) and fanned out to status
listeners; auto-sync always leaves conflict auto-resolution off (H4), recording true two-sided
conflicts as visible pending state instead of LWW.

## App hooks (H5/H6)

App-specific differences survive as hooks, not config: `onPeriodicTick` (MyAnime/MyDevice run daily
`BackupService.runAutoBackupIfNeeded` here; MyDay leaves it null because its `ReminderService` 30s
loop owns backup - H5) and `onResume` (MyAnime: backup + reminders; MyDay: mobile reminder refresh;
MyDevice: backup only - H6). `consumeLocalDataChanged` is wired to
`WebDavSyncEngine.consumeLocalDataChanged` so `_trySync` and `notifyLocalDataChangedIfNeeded` reload
open pages exactly when the engine wrote local data or downloaded images.
