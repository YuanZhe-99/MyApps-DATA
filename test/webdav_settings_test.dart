import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

/// Purpose: Verify connection editing and busy action boundaries.
/// Inputs: None. Returns: None. Side effects: Registers tests.
/// Notes: No network or credentials are persisted.
void main() {
  testWidgets(
    'connection fields use caller controllers and endpoint callbacks',
    (tester) async {
      final controllers = List.generate(4, (_) => TextEditingController());
      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
        }
      });
      String? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyAppsWebDavSettings(
              urlController: controllers[0],
              usernameController: controllers[1],
              passwordController: controllers[2],
              pathController: controllers[3],
              urlLabel: 'Server',
              usernameLabel: 'User',
              passwordLabel: 'Password',
              pathLabel: 'Path',
              pathHint: '/Example',
              onUrlChanged: (v) => changed = v,
              afterUrl: const Text('Endpoint policy'),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com',
      );
      expect(changed, 'https://example.com');
      expect(controllers[0].text, changed);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
        true,
      );
      expect(find.text('Endpoint policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('busy sync disables manual and force operations', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyAppsWebDavSyncActions(
            syncing: true,
            syncLabel: 'Sync',
            syncingLabel: 'Syncing',
            uploadLabel: 'Upload',
            downloadLabel: 'Download',
            onSync: () => calls++,
            onUpload: () => calls++,
            onDownload: () => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Upload'));
    await tester.tap(find.text('Download'));
    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
