import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

class _Hooks {
  _Hooks() {
    active = true;
  }

  bool active = true;
  int syncCalls = 0;
  int periodicTicks = 0;
  int resumeCalls = 0;
  bool localChangedFlag = false;
  int localChangedConsumed = 0;
  AutoSyncResult nextResult = const AutoSyncResult(success: true);
  Object? syncError;
  final List<void Function()> reloadCbs = [];
  final List<void Function()> statusCbs = [];
}

AutoSyncScheduler _scheduler(_Hooks h, {DateTime Function()? clock}) {
  return AutoSyncScheduler(
    isAutoSyncActive: () async => h.active,
    runSync: () async {
      h.syncCalls++;
      if (h.syncError != null) {
        throw h.syncError!;
      }
      return h.nextResult;
    },
    consumeLocalDataChanged: () {
      h.localChangedConsumed++;
      final v = h.localChangedFlag;
      h.localChangedFlag = false;
      return v;
    },
    onPeriodicTick: () async {
      h.periodicTicks++;
    },
    onResume: () async {
      h.resumeCalls++;
    },
    clock: clock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('_started guard: notifySaved is ignored before start', () {
    final h = _Hooks();
    final s = _scheduler(h);
    s.notifySaved();
    expect(h.syncCalls, 0);
  });

  test('start runs an immediate sync and registers reload listeners', () async {
    final h = _Hooks();
    final s = _scheduler(h);
    var reloaded = 0;
    s.addOnLocalDataChanged(() => reloaded++);
    var statusChanges = 0;
    s.addOnStatusChanged(() => statusChanges++);

    s.start();
    // Immediate sync is unawaited; pump until it completes.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(h.syncCalls, 1);
    expect(s.lastSuccessAt, isNotNull);
    expect(s.lastError, isNull);
    expect(statusChanges, greaterThan(0));
    expect(reloaded, 0);
    s.stop();
  });

  test('sync is skipped when auto-sync is not active', () async {
    final h = _Hooks()..active = false;
    final s = _scheduler(h);
    s.start();
    await Future<void>.delayed(Duration.zero);
    expect(h.syncCalls, 0);
    s.stop();
  });

  test(
    'overlapping triggers are silently skipped by the syncing guard',
    () async {
      final h = _Hooks();
      final gate = Completer<void>();
      h.nextResult = const AutoSyncResult(success: true);
      var syncStarted = 0;
      final s = AutoSyncScheduler(
        isAutoSyncActive: () async => true,
        runSync: () async {
          syncStarted++;
          await gate.future;
          return const AutoSyncResult(success: true);
        },
        consumeLocalDataChanged: () => false,
      );

      s.requestSyncNow();
      // Let the first attempt pass its config gate and acquire the guard.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(syncStarted, 1);

      s.requestSyncNow();
      s.requestSyncNow();
      await Future<void>.delayed(Duration.zero);
      expect(syncStarted, 1);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      s.stop();
    },
  );

  test(
    'two triggers while the config gate is pending run exactly one sync',
    () {
      FakeAsync().run((async) {
        var syncCalls = 0;
        final s = AutoSyncScheduler(
          // The gate takes time to answer, so both triggers arrive before
          // either has had a chance to acquire the syncing guard.
          isAutoSyncActive: () async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return true;
          },
          runSync: () async {
            syncCalls++;
            return const AutoSyncResult(success: true);
          },
          consumeLocalDataChanged: () => false,
        );

        s.requestSyncNow();
        s.requestSyncNow();
        async.elapse(const Duration(milliseconds: 50));
        async.flushMicrotasks();

        expect(syncCalls, 1);
        expect(s.lastError, isNull);
        s.stop();
      });
    },
  );

  test('an inactive config gate releases the guard for a later trigger', () {
    FakeAsync().run((async) {
      var active = false;
      var syncCalls = 0;
      final s = AutoSyncScheduler(
        isAutoSyncActive: () async => active,
        runSync: () async {
          syncCalls++;
          return const AutoSyncResult(success: true);
        },
        consumeLocalDataChanged: () => false,
      );

      s.requestSyncNow();
      async.flushMicrotasks();
      expect(syncCalls, 0);

      active = true;
      s.requestSyncNow();
      async.flushMicrotasks();
      expect(syncCalls, 1);
      s.stop();
    });
  });

  test('notifySaved debounces 30s to a single trailing sync', () {
    final h = _Hooks();
    final s = _scheduler(h);
    FakeAsync().run((async) {
      s.start();
      async.flushMicrotasks();
      h.syncCalls = 0;
      s.notifySaved();
      s.notifySaved();
      s.notifySaved();
      async.elapse(const Duration(seconds: 29));
      expect(h.syncCalls, 0);
      async.elapse(const Duration(seconds: 1));
      expect(h.syncCalls, 1);
    });
    s.stop();
  });

  test('requestSyncNow cancels a pending debounce', () {
    final h = _Hooks();
    final s = _scheduler(h);
    FakeAsync().run((async) {
      s.start();
      async.flushMicrotasks();
      h.syncCalls = 0;
      s.notifySaved();
      async.elapse(const Duration(seconds: 10));
      s.requestSyncNow();
      async.flushMicrotasks();
      expect(h.syncCalls, 1);
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(h.syncCalls, 1);
    });
    s.stop();
  });

  test('periodic timer fires sync plus onPeriodicTick every 15 minutes', () {
    final h = _Hooks();
    final s = _scheduler(h);
    FakeAsync().run((async) {
      s.start();
      async.flushMicrotasks();
      h.syncCalls = 0;
      async.elapse(const Duration(minutes: 15));
      async.flushMicrotasks();
      expect(h.syncCalls, greaterThanOrEqualTo(1));
      expect(h.periodicTicks, 1);
      async.elapse(const Duration(minutes: 15));
      async.flushMicrotasks();
      expect(h.periodicTicks, 2);
    });
    s.stop();
  });

  test('resume triggers sync and onResume side effect', () async {
    final h = _Hooks();
    final s = _scheduler(h);
    s.start();
    await Future<void>.delayed(Duration.zero);
    h.syncCalls = 0;
    h.resumeCalls = 0;

    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(h.syncCalls, 1);
    expect(h.resumeCalls, 1);
    s.stop();
  });

  test('non-resumed lifecycle states do nothing', () async {
    final h = _Hooks();
    final s = _scheduler(h);
    s.start();
    await Future<void>.delayed(Duration.zero);
    h.syncCalls = 0;

    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    s.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);

    expect(h.syncCalls, 0);
    expect(h.resumeCalls, 0);
    s.stop();
  });

  group('non-success sync outcomes are recorded', () {
    // Each row: how the attempt ends, and what the status must show.
    final cases =
        <
          ({
            String name,
            AutoSyncResult? result,
            Object? thrown,
            String errorContains,
            bool conflicts,
          })
        >[
          (
            name: 'failure result records lastError and failure time',
            result: const AutoSyncResult(success: false, error: 'boom'),
            thrown: null,
            errorContains: 'boom',
            conflicts: false,
          ),
          (
            name: 'conflict result sets hasPendingConflicts',
            result: const AutoSyncResult(success: true, hasConflicts: true),
            thrown: null,
            errorContains: 'manual resolution',
            conflicts: true,
          ),
          (
            name: 'runSync exception is caught and recorded',
            result: null,
            thrown: Exception('network down'),
            errorContains: 'network down',
            conflicts: false,
          ),
        ];

    for (final c in cases) {
      test(c.name, () async {
        final h = _Hooks();
        final now = DateTime(2026, 7, 24, 12);
        final s = _scheduler(h, clock: () => now);
        if (c.result != null) h.nextResult = c.result!;
        h.syncError = c.thrown;

        s.requestSyncNow();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(s.lastError, contains(c.errorContains));
        expect(s.lastFailureAt, now);
        expect(s.hasPendingConflicts, c.conflicts);
        s.stop();
      });
    }
  });

  test(
    'local-data-changed flag fires reload listeners once after sync',
    () async {
      final h = _Hooks();
      final s = _scheduler(h);
      var reloaded = 0;
      s.addOnLocalDataChanged(() => reloaded++);
      h.localChangedFlag = true;

      s.requestSyncNow();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(reloaded, 1);
      expect(h.localChangedConsumed, 1);
      s.stop();
    },
  );

  test('notifyLocalDataChangedIfNeeded consumes the flag', () {
    final h = _Hooks();
    final s = _scheduler(h);
    var reloaded = 0;
    s.addOnLocalDataChanged(() => reloaded++);
    h.localChangedFlag = true;

    s.notifyLocalDataChangedIfNeeded();
    expect(reloaded, 1);
    expect(h.localChangedConsumed, 1);

    s.notifyLocalDataChangedIfNeeded();
    expect(reloaded, 1);
    expect(h.localChangedConsumed, 2);
  });

  test('notifyLocalDataChangedNow fires unconditionally', () {
    final h = _Hooks();
    final s = _scheduler(h);
    var reloaded = 0;
    s.addOnLocalDataChanged(() => reloaded++);

    s.notifyLocalDataChangedNow();
    s.notifyLocalDataChangedNow();
    expect(reloaded, 2);
  });

  test('recordSyncResult maps success/conflict/failure', () {
    final h = _Hooks();
    final now = DateTime(2026, 7, 24, 13);
    final s = _scheduler(h, clock: () => now);

    s.recordSyncResult(const AutoSyncResult(success: true));
    expect(s.lastSuccessAt, now);
    expect(s.hasPendingConflicts, isFalse);

    s.recordSyncResult(
      const AutoSyncResult(success: true, hasConflicts: true, error: 'x'),
    );
    expect(s.hasPendingConflicts, isTrue);
    expect(s.lastError, contains('manual resolution'));

    s.recordSyncResult(const AutoSyncResult(success: false, error: 'fail'));
    expect(s.hasPendingConflicts, isFalse);
    expect(s.lastError, 'fail');
  });

  test('recordFinalizeResult records success or failure', () {
    final h = _Hooks();
    final now = DateTime(2026, 7, 24, 14);
    final s = _scheduler(h, clock: () => now);

    s.recordFinalizeResult(true);
    expect(s.lastSuccessAt, now);

    s.recordFinalizeResult(false);
    expect(s.lastError, 'Failed to upload resolved sync conflicts');
    expect(s.lastFailureAt, now);
  });

  test('status listeners fire on success and failure', () async {
    final h = _Hooks();
    final s = _scheduler(h);
    var changes = 0;
    s.addOnStatusChanged(() => changes++);

    s.requestSyncNow();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final afterSuccess = changes;

    h.nextResult = const AutoSyncResult(success: false, error: 'e');
    s.requestSyncNow();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(changes, greaterThan(afterSuccess));
    s.stop();
  });

  test('stop cancels timers and observer', () {
    final h = _Hooks();
    final s = _scheduler(h);
    s.start();
    s.stop();
    FakeAsync().run((async) {
      s.notifySaved();
      async.elapse(const Duration(seconds: 30));
      expect(h.syncCalls, 0);
    });
  });

  test('onPeriodicTick is null for MyDay-style configs', () async {
    final h = _Hooks();
    final s = AutoSyncScheduler(
      isAutoSyncActive: () async => h.active,
      runSync: () async {
        h.syncCalls++;
        return h.nextResult;
      },
      consumeLocalDataChanged: () => false,
    );
    s.start();
    await Future<void>.delayed(Duration.zero);
    FakeAsync().run((async) {
      async.elapse(const Duration(minutes: 15));
      expect(h.syncCalls, greaterThanOrEqualTo(1));
      expect(h.periodicTicks, 0);
    });
    s.stop();
  });
}
