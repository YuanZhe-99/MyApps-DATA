import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

/// Purpose: Verify backup callbacks and data action presentation.
/// Inputs: None. Returns: None. Side effects: Registers tests.
/// Notes: No engine or persistence is needed.
void main() {
  testWidgets('backup controls forward preferences without storage', (tester) async {
    bool? enabled;
    int? retention;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 350,
      child: MyAppsBackupSettings(
        autoBackupTitle: 'Daily backup', autoBackupDescription: 'Save daily',
        autoBackup: false, onAutoBackupChanged: (v) => enabled = v,
        retentionTitle: 'Retention', retentionDays: 7, retentionOptions: const [7, 30],
        retentionLabel: (v) => '$v days', onRetentionChanged: (v) => retention = v,
      ),
    ))));
    await tester.tap(find.byType(Switch));
    expect(enabled, true);
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 days').last);
    await tester.pumpAndSettle();
    expect(retention, 30);
    expect(tester.takeException(), isNull);
  });
}
