import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

final _labels = MyAppsTrustedHostWarningLabels(
  title: 'Trust this host?',
  body: (host) => 'Keys to $host travel unencrypted.',
  acknowledgement: 'I understand the risk',
  confirmLabel: 'Trust anyway',
  cancelLabel: 'Cancel',
);

Future<Future<bool>> _open(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    ),
  );
  final result = showMyAppsTrustedHostWarning(
    context,
    host: 'dav.example.com',
    labels: _labels,
  );
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('normalizeTrustedHostEntry', () {
    test('accepts hosts, wildcards and addresses, lowercased', () {
      expect(normalizeTrustedHostEntry(' NAS.Example.com '), 'nas.example.com');
      expect(normalizeTrustedHostEntry('*.example.com'), '*.example.com');
      expect(normalizeTrustedHostEntry('203.0.113.7'), '203.0.113.7');
    });

    test('refuses URLs, ports, paths and blanks', () {
      expect(normalizeTrustedHostEntry('http://nas/dav'), isNull);
      expect(normalizeTrustedHostEntry('nas:8080'), isNull);
      expect(normalizeTrustedHostEntry('nas/dav'), isNull);
      expect(normalizeTrustedHostEntry('  '), isNull);
      expect(normalizeTrustedHostEntry('*.'), isNull);
    });

    test('a normalised entry is what the policy trusts', () {
      final entry = normalizeTrustedHostEntry('DAV.Example.com')!;
      expect(
        evaluateEndpointUrl(
          'http://dav.example.com/x',
          trustedHosts: [entry],
        ).reason,
        EndpointReason.trustedHost,
      );
    });
  });

  testWidgets('confirm stays disabled until the risk is acknowledged', (
    tester,
  ) async {
    final result = await _open(tester);
    expect(find.text('Keys to dav.example.com travel unencrypted.'), findsOne);
    await tester.tap(find.text('Trust anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Trust this host?'), findsOne, reason: 'still open');
    await tester.tap(find.text('I understand the risk'));
    await tester.pump();
    await tester.tap(find.text('Trust anyway'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel and dismissal decline', (tester) async {
    var result = await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = await _open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
