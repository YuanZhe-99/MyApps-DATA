// Unit tests for the verbatim-moved sync_progress.dart (P2.1).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

void main() {
  group('SyncPhase', () {
    test('has the expected phases in order', () {
      expect(SyncPhase.values, [
        SyncPhase.idle,
        SyncPhase.connecting,
        SyncPhase.downloadingData,
        SyncPhase.merging,
        SyncPhase.uploadingData,
        SyncPhase.uploadingImages,
        SyncPhase.downloadingImages,
        SyncPhase.done,
        SyncPhase.error,
      ]);
    });
  });

  group('SyncProgress', () {
    test('idle constant is the resting state', () {
      expect(SyncProgress.idle.phase, SyncPhase.idle);
      expect(SyncProgress.idle.isRunning, isFalse);
    });

    test('fraction is null when total is zero (indeterminate)', () {
      const p = SyncProgress(SyncPhase.downloadingData, current: 1, total: 0);
      expect(p.fraction, isNull);
    });

    test('fraction clamps current/total into 0..1', () {
      const half = SyncProgress(SyncPhase.uploadingData, current: 1, total: 2);
      expect(half.fraction, 0.5);
      const over = SyncProgress(SyncPhase.uploadingData, current: 5, total: 2);
      expect(over.fraction, 1.0);
    });

    test('isRunning is false for idle/done/error, true otherwise', () {
      expect(const SyncProgress(SyncPhase.idle).isRunning, isFalse);
      expect(const SyncProgress(SyncPhase.done).isRunning, isFalse);
      expect(const SyncProgress(SyncPhase.error).isRunning, isFalse);
      expect(const SyncProgress(SyncPhase.connecting).isRunning, isTrue);
      expect(const SyncProgress(SyncPhase.merging).isRunning, isTrue);
      expect(const SyncProgress(SyncPhase.uploadingImages).isRunning, isTrue);
    });

    test('carries optional detail', () {
      const p = SyncProgress(SyncPhase.error, detail: 'boom');
      expect(p.detail, 'boom');
    });
  });

  group('SyncProgressListenable', () {
    test('is a ValueListenable<SyncProgress>', () {
      final ValueNotifier<SyncProgress> notifier = ValueNotifier(
        SyncProgress.idle,
      );
      SyncProgressListenable listenable = notifier;
      expect(listenable.value.phase, SyncPhase.idle);
      notifier.dispose();
    });
  });
}
