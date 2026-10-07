import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

/// Purpose: Verify privacy notice content, decisions and paused banner.
/// Inputs: None. Returns: None. Side effects: Registers tests.
/// Notes: No network or storage is involved.
void main() {
  final labels = MyAppsWebDavPrivacyNoticeLabels(
    title: 'Before you sync',
    intro: 'Intro',
    modulesHeading: 'Uploaded data',
    optionalContentHeading: 'Optional content',
    destinationHeading: 'Destination',
    encryptionHeading: 'Encryption',
    transportHeading: 'Connection',
    transportDescription: (v) => 'Transport: ${v.security.name}',
    insecureHttpWarning: 'Unencrypted connection',
    noThirdPartiesStatement: 'No third parties',
    confirmLabel: 'Enable sync',
    declineLabel: 'Not now',
  );

  /// Purpose: Pump a button that opens the notice and records the result.
  /// Inputs: [tester], endpoint [url] and [onResult].
  /// Returns: None. Side effects: Pumps widgets and opens the dialog.
  /// Notes: Internal helper.
  Future<void> open(
    WidgetTester tester,
    String url,
    ValueChanged<bool> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showMyAppsWebDavPrivacyNotice(
                context,
                labels: labels,
                modules: const [
                  MyAppsWebDavPrivacyItem(title: 'Tasks', description: 'All'),
                ],
                optionalContent: const [
                  MyAppsWebDavPrivacyItem(title: 'Audio'),
                ],
                destinationHost: Uri.parse(url).host,
                encryptionStatement: 'Stored unencrypted',
                verdict: evaluateEndpointUrl(url),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirming returns true and shows the inventory', (
    tester,
  ) async {
    bool? result;
    await open(tester, 'https://dav.example.com/dav', (v) => result = v);
    for (final text in [
      'Before you sync',
      'Tasks',
      'All',
      'Audio',
      'dav.example.com',
      'No third parties',
      'Stored unencrypted',
      'Transport: encrypted',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Unencrypted connection'), findsNothing);
    await tester.tap(find.text('Enable sync'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('declining returns false', (tester) async {
    bool? result;
    await open(tester, 'http://192.168.1.5/dav', (v) => result = v);
    expect(find.text('Transport: privateNetwork'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('dismissing counts as declining', (tester) async {
    bool? result;
    await open(tester, 'https://dav.example.com', (v) => result = v);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('insecure HTTP shows the extra warning', (tester) async {
    await open(tester, 'http://dav.example.com/dav', (_) {});
    expect(find.text('Transport: insecureHttp'), findsOneWidget);
    expect(find.text('Unencrypted connection'), findsOneWidget);
  });

  testWidgets('paused banner forwards the review action', (tester) async {
    var reviewed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyAppsWebDavSyncPausedBanner(
            message: 'Sync paused until you review the privacy notice',
            reviewLabel: 'Review',
            onReview: () => reviewed++,
          ),
        ),
      ),
    );
    expect(
      find.text('Sync paused until you review the privacy notice'),
      findsOneWidget,
    );
    await tester.tap(find.text('Review'));
    expect(reviewed, 1);
  });
}
