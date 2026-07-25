// Unit tests for the verbatim-moved sync_wake_lock.dart (P2.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';
import 'package:wakelock_plus/wakelock_plus.dart'
    show wakelockPlusPlatformInstance;
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// Purpose: Fake wakelock platform that records enable/disable transitions.
/// Inputs: None.
/// Returns: A `WakelockPlusPlatformInterface` test double.
/// Side effects: Tracks an in-memory enabled flag and a call log.
/// Notes: The real plugin is a platform channel; this fake lets the ref-counting
/// and ownership logic be tested deterministically.
class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  bool _enabled = false;
  final List<bool> toggles = [];

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWakelockPlatform platform;

  setUp(() {
    platform = _FakeWakelockPlatform();
    WakelockPlusPlatformInterface.instance = platform;
    // wakelock_plus caches the platform instance when its library loads.
    wakelockPlusPlatformInstance = platform;
  });

  test('single acquire enables once; matching release disables', () async {
    await SyncWakeLock.acquire();
    expect(platform.toggles, [true]);

    await SyncWakeLock.release();
    expect(platform.toggles, [true, false]);
  });

  test(
    'overlapping acquires share one lock; disabled only after last release',
    () async {
      await SyncWakeLock.acquire();
      await SyncWakeLock.acquire();
      await SyncWakeLock.acquire();
      // Only the first acquire toggles the platform lock.
      expect(platform.toggles, [true]);

      await SyncWakeLock.release();
      await SyncWakeLock.release();
      // Still held by one reference; no disable yet.
      expect(platform.toggles, [true]);

      await SyncWakeLock.release();
      expect(platform.toggles, [true, false]);
    },
  );

  test(
    'does not disable a lock that was already enabled by another feature',
    () async {
      // Another feature already holds the platform wake lock.
      await platform.toggle(enable: true);
      platform.toggles.clear();

      await SyncWakeLock.acquire();
      // Already enabled -> sync does not claim ownership.
      expect(platform.toggles, isEmpty);

      await SyncWakeLock.release();
      // Must NOT disable a lock it did not enable.
      expect(platform.toggles, isEmpty);
      expect(await platform.enabled, isTrue);
    },
  );

  test('release with nothing held is a safe no-op', () async {
    await SyncWakeLock.release();
    expect(platform.toggles, isEmpty);
  });

  test('a fresh acquire after full release re-enables', () async {
    await SyncWakeLock.acquire();
    await SyncWakeLock.release();
    platform.toggles.clear();

    await SyncWakeLock.acquire();
    expect(platform.toggles, [true]);
    await SyncWakeLock.release();
  });
}
