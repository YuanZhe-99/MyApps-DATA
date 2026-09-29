// Unit tests for the verbatim-moved sync_progress.dart (P2.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

void main() {
  test('SyncPhase has the expected phases in order', () {
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

  test(
    'SyncProgress.isRunning is false for idle/done/error, true otherwise',
    () {
      expect(SyncProgress.idle.phase, SyncPhase.idle);
      for (final phase in SyncPhase.values) {
        final resting =
            phase == SyncPhase.idle ||
            phase == SyncPhase.done ||
            phase == SyncPhase.error;
        expect(SyncProgress(phase).isRunning, !resting, reason: '$phase');
      }
      expect(SyncProgress.idle.isRunning, isFalse);
    },
  );

  test(
    'SyncProgress.fraction is null for zero total, else clamped to 0..1',
    () {
      const indeterminate = SyncProgress(
        SyncPhase.downloadingData,
        current: 1,
        total: 0,
      );
      const half = SyncProgress(SyncPhase.uploadingData, current: 1, total: 2);
      const over = SyncProgress(SyncPhase.uploadingData, current: 5, total: 2);
      expect(indeterminate.fraction, isNull);
      expect(half.fraction, 0.5);
      expect(over.fraction, 1.0);
    },
  );
}
