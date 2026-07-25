/// Purpose: Generic auto-sync scheduler core extracted from the three apps'
/// `auto_sync_service.dart` singletons (feature-matrix §H).
/// Inputs: App-provided hooks for config-gating, sync execution, the
/// local-data-changed signal, and optional periodic/resume side effects.
/// Returns: Lifecycle-observed, debounced, periodic auto-sync orchestration
/// plus in-memory status and reload-listener fan-out.
/// Side effects: Registers a [WidgetsBindingObserver], starts/stops timers,
/// and invokes app hooks that may perform network sync, backup, or reminder
/// refresh.
/// Notes: The scheduler owns only the trigger topology and status recording;
/// the actual sync runs through [runSync] (typically delegating to
/// `WebDavSyncEngine.sync`). App-specific side effects stay app-side via the
/// [onPeriodicTick] and [onResume] hooks so MyDay's ReminderService-driven
/// backup is preserved (H5) and the three resume side-effect sets survive
/// unchanged (H6). Launch/periodic/resume triggers are unified on canceling
/// a pending save-debounce before syncing immediately (MyAnime's behavior);
/// [notifySaved] is the only trailing-edge debounced trigger.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Purpose: Report one auto-sync attempt outcome for status recording.
/// Inputs: None (constructed by the app's [AutoSyncRunSync] hook).
/// Returns: An immutable result.
/// Side effects: None.
/// Notes: Apps build this from their sync result (e.g. `EngineSyncResult`):
/// `hasConflicts` is true when a pending conflict state was produced.
class AutoSyncResult {
  /// Purpose: Create an auto-sync result.
  /// Inputs: [success], optional [hasConflicts] and [error].
  /// Returns: A new [AutoSyncResult].
  /// Side effects: None.
  /// Notes: None.
  const AutoSyncResult({
    required this.success,
    this.hasConflicts = false,
    this.error,
  });

  /// Whether the sync completed without an error.
  final bool success;

  /// Whether the sync produced unresolved record conflicts.
  final bool hasConflicts;

  /// Joined error message, when any.
  final String? error;
}

/// Purpose: Return whether auto-sync is configured and enabled.
/// Inputs: None.
/// Returns: True when the persisted config is configured with auto-sync on.
/// Side effects: App-defined (typically reads `webdav_config.json`).
/// Notes: The scheduler gates on this BEFORE acquiring its sync guard, so a
/// not-configured attempt never blocks a later real sync.
typedef AutoSyncPredicate = Future<bool> Function();

/// Purpose: Execute one auto-sync attempt and report its outcome.
/// Inputs: None.
/// Returns: The sync outcome for status recording.
/// Side effects: App-defined (typically `WebDavSyncEngine.sync`).
/// Notes: The hook must NOT consume the engine's local-data-changed flag;
/// the scheduler consumes it separately via [consumeLocalDataChanged] after
/// the sync returns. Auto-sync always leaves conflict auto-resolution off
/// (H4); the hook should call sync without `autoResolve`.
typedef AutoSyncRunSync = Future<AutoSyncResult> Function();

/// Purpose: Consume the engine's sticky local-data-changed flag.
/// Inputs: None.
/// Returns: Whether unconsumed engine work changed local data or images.
/// Side effects: Resets the flag to false.
/// Notes: Wired to `WebDavSyncEngine.consumeLocalDataChanged`.
typedef AutoSyncConsumeLocalDataChanged = bool Function();

/// Purpose: Run an app-specific periodic or resume side effect.
/// Inputs: None.
/// Returns: A future completing after the side effect.
/// Side effects: App-defined (backup, reminder refresh, etc.).
/// Notes: Errors are swallowed by the scheduler so a side-effect failure can
/// never crash a timer or lifecycle callback.
typedef AutoSyncSideEffect = FutureOr<void> Function();

/// Generic lifecycle-observed auto-sync scheduler.
class AutoSyncScheduler with WidgetsBindingObserver {
  /// Purpose: Create an auto-sync scheduler.
  /// Inputs: [isAutoSyncActive] and [runSync] hooks, optional
  /// [consumeLocalDataChanged], [onPeriodicTick], [onResume] hooks, fixed
  /// [debounceDuration] (30s) and [periodicInterval] (15min), and a [clock]
  /// for status timestamps.
  /// Returns: A new [AutoSyncScheduler].
  /// Side effects: None until [start] is called.
  /// Notes: All durations are fixed invariants (H1/H2); [clock] defaults to
  /// [DateTime.now] and is injectable for tests.
  AutoSyncScheduler({
    required this.isAutoSyncActive,
    required this.runSync,
    this.consumeLocalDataChanged,
    this.onPeriodicTick,
    this.onResume,
    this.debounceDuration = const Duration(seconds: 30),
    this.periodicInterval = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Fixed trailing-edge save-debounce window (H2).
  final Duration debounceDuration;

  /// Fixed periodic sync interval (H1).
  final Duration periodicInterval;

  /// App hook: is auto-sync configured and enabled?
  final AutoSyncPredicate isAutoSyncActive;

  /// App hook: execute one sync attempt.
  final AutoSyncRunSync runSync;

  /// App hook: consume the engine local-data-changed flag.
  final AutoSyncConsumeLocalDataChanged? consumeLocalDataChanged;

  /// Optional periodic side effect (H5; MyAnime/MyDevice run daily backup
  /// here, MyDay leaves it null because its ReminderService owns backup).
  final AutoSyncSideEffect? onPeriodicTick;

  /// Optional resume side effect (H6; app-specific bundle such as backup
  /// and/or reminder refresh), run after the resume sync is kicked off.
  final AutoSyncSideEffect? onResume;

  final DateTime Function() _clock;

  Timer? _debounce;
  Timer? _periodic;
  bool _syncing = false;
  bool _started = false;

  DateTime? _lastSuccessAt;
  DateTime? _lastFailureAt;
  String? _lastError;
  bool _hasPendingConflicts = false;

  final List<void Function()> _onLocalDataChanged = [];
  final List<void Function()> _onStatusChanged = [];

  /// Time of the last successful sync, if any.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Time of the last failed sync, if any.
  DateTime? get lastFailureAt => _lastFailureAt;

  /// Last sync error message, if any.
  String? get lastError => _lastError;

  /// Whether a pending conflict is awaiting manual resolution.
  bool get hasPendingConflicts => _hasPendingConflicts;

  /// Purpose: Register a UI reload callback.
  /// Inputs: [callback].
  /// Returns: None.
  /// Side effects: Appends to the reload-listener list.
  /// Notes: UI pages call this in `initState` and remove in `dispose`.
  void addOnLocalDataChanged(void Function() callback) =>
      _onLocalDataChanged.add(callback);

  /// Purpose: Unregister a UI reload callback.
  /// Inputs: [callback].
  /// Returns: None.
  /// Side effects: Removes the callback if present.
  /// Notes: None.
  void removeOnLocalDataChanged(void Function() callback) =>
      _onLocalDataChanged.remove(callback);

  /// Purpose: Register a status-change callback.
  /// Inputs: [callback].
  /// Returns: None.
  /// Side effects: Appends to the status-listener list.
  /// Notes: Settings/WebDAV pages call this to refresh sync-health banners.
  void addOnStatusChanged(void Function() callback) =>
      _onStatusChanged.add(callback);

  /// Purpose: Unregister a status-change callback.
  /// Inputs: [callback].
  /// Returns: None.
  /// Side effects: Removes the callback if present.
  /// Notes: None.
  void removeOnStatusChanged(void Function() callback) =>
      _onStatusChanged.remove(callback);

  /// Purpose: Record a manual sync result through the same status path.
  /// Inputs: [result].
  /// Returns: None.
  /// Side effects: Updates sync status and notifies status listeners.
  /// Notes: Manual sync pages call this so status banners clear after success.
  void recordSyncResult(AutoSyncResult result) {
    if (result.hasConflicts) {
      _recordFailure(
        'Sync conflicts require manual resolution'
        '${result.error != null ? ': ${result.error}' : ''}',
        conflicts: true,
      );
    } else if (!result.success) {
      _recordFailure(result.error ?? 'Unknown sync failure');
    } else {
      _recordSuccess();
    }
  }

  /// Purpose: Record a conflict-finalization result.
  /// Inputs: [ok].
  /// Returns: None.
  /// Side effects: Updates sync status and notifies status listeners.
  /// Notes: Used after users resolve conflicts manually.
  void recordFinalizeResult(bool ok) {
    if (ok) {
      _recordSuccess();
    } else {
      _recordFailure('Failed to upload resolved sync conflicts');
    }
  }

  /// Purpose: Notify UI reload listeners when the local-data-changed flag is
  /// set.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Consumes the flag and invokes registered reload callbacks.
  /// Notes: Manual sync/force pages call this so open pages reload without
  /// waiting for the next background sync.
  void notifyLocalDataChangedIfNeeded() {
    if (consumeLocalDataChanged?.call() ?? false) {
      _fireLocalDataChanged();
    }
  }

  /// Purpose: Notify UI reload listeners unconditionally.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Invokes registered reload callbacks.
  /// Notes: Used after local data files were replaced outside of sync
  /// (backup restore, ZIP import). Does not touch the local-data-changed flag.
  void notifyLocalDataChangedNow() {
    _fireLocalDataChanged();
  }

  /// Purpose: Start observing lifecycle and run the first sync.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Registers a [WidgetsBindingObserver], starts the periodic
  /// timer, and kicks off an immediate sync (canceling any pending debounce).
  /// Notes: Idempotent via an internal `_started` flag. The periodic timer
  /// also runs [onPeriodicTick] (e.g. daily auto-backup for MyAnime/MyDevice)
  /// so a desktop instance left running across midnight still fires it.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _requestSyncNow();
    _periodic = Timer.periodic(periodicInterval, (_) {
      _requestSyncNow();
      _invokeSideEffect(onPeriodicTick);
    });
  }

  /// Purpose: Stop observing lifecycle and cancel timers.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Cancels the debounce and periodic timers and removes the
  /// observer.
  /// Notes: None.
  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _periodic?.cancel();
    _periodic = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }

  /// Purpose: Schedule a trailing-edge debounced sync after a storage save.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Resets the debounce timer to [debounceDuration].
  /// Notes: Ignored before [start] so early storage writes cannot schedule a
  /// sync while the service is not yet observing the app lifecycle.
  void notifySaved() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, _trySync);
  }

  /// Purpose: Request an immediate sync, canceling any pending debounce.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Cancels the debounce timer and kicks off a guarded sync.
  /// Notes: Used right after enabling/saving WebDAV auto-sync configuration.
  void requestSyncNow() => _requestSyncNow();

  /// Purpose: React to app lifecycle changes.
  /// Inputs: [state].
  /// Returns: None.
  /// Side effects: On `resumed`, kicks off an immediate sync (canceling any
  /// pending debounce) and runs the optional [onResume] side effect.
  /// Notes: Only `resumed` triggers sync (H3). Resume side effects are
  /// app-specific (H6).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _requestSyncNow();
    _invokeSideEffect(onResume);
  }

  /// Purpose: Cancel the debounce and kick off a guarded sync.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Cancels `_debounce` and starts `_trySync` unawaited.
  /// Notes: Internal helper; the launch/periodic/resume triggers all route
  /// through here so a pending save-debounce is always superseded.
  void _requestSyncNow() {
    _debounce?.cancel();
    _debounce = null;
    unawaited(_trySync());
  }

  /// Purpose: Run one guarded sync attempt and record its status.
  /// Inputs: None.
  /// Returns: A future completing after the attempt.
  /// Side effects: Calls [runSync], records status, and fires reload
  /// listeners when the local-data-changed flag was set.
  /// Notes: The `_syncing` guard silently skips overlapping triggers (H1).
  /// The config gate runs before the guard is acquired so a not-configured
  /// attempt never blocks a later real sync.
  Future<void> _trySync() async {
    if (_syncing) return;
    if (!await isAutoSyncActive()) return;
    _syncing = true;
    try {
      final result = await runSync();
      if (result.hasConflicts) {
        _recordFailure(
          'Sync conflicts require manual resolution'
          '${result.error != null ? ': ${result.error}' : ''}',
          conflicts: true,
        );
      } else if (!result.success) {
        _recordFailure(result.error ?? 'Unknown sync failure');
      } else {
        _recordSuccess();
      }
      if (consumeLocalDataChanged?.call() ?? false) {
        _fireLocalDataChanged();
      }
    } catch (e) {
      _recordFailure(e.toString());
    } finally {
      _syncing = false;
    }
  }

  /// Purpose: Run an optional side-effect hook, swallowing errors.
  /// Inputs: [hook].
  /// Returns: A future completing after the hook (or immediately if null).
  /// Side effects: App-defined.
  /// Notes: A side-effect failure must never crash a timer or lifecycle
  /// callback, so errors are deliberately swallowed.
  Future<void> _invokeSideEffect(AutoSyncSideEffect? hook) async {
    if (hook == null) return;
    try {
      await hook();
    } catch (_) {}
  }

  /// Purpose: Record a successful sync.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Updates status fields and notifies status listeners.
  /// Notes: Clears the last error and pending-conflict flag.
  void _recordSuccess() {
    _lastSuccessAt = _clock();
    _lastError = null;
    _hasPendingConflicts = false;
    _notifyStatusChanged();
  }

  /// Purpose: Record a failed sync or pending conflicts.
  /// Inputs: [error], optional [conflicts].
  /// Returns: None.
  /// Side effects: Updates status fields and notifies status listeners.
  /// Notes: None.
  void _recordFailure(String error, {bool conflicts = false}) {
    _lastFailureAt = _clock();
    _lastError = error;
    _hasPendingConflicts = conflicts;
    _notifyStatusChanged();
  }

  /// Purpose: Invoke all reload listeners with a snapshot copy.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Calls each registered reload callback.
  /// Notes: Snapshots the list so a callback that mutates it during
  /// iteration is safe.
  void _fireLocalDataChanged() {
    for (final cb in List.of(_onLocalDataChanged)) {
      cb();
    }
  }

  /// Purpose: Invoke all status listeners with a snapshot copy.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Calls each registered status callback.
  /// Notes: None.
  void _notifyStatusChanged() {
    for (final cb in List.of(_onStatusChanged)) {
      cb();
    }
  }
}
