import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

import 'dart:io';

/// Purpose: In-memory storage adapter for acknowledgement persistence tests.
/// Inputs: None. Returns: None. Side effects: Mutates [config] only.
/// Notes: Never touches the file system.
class _MemoryStorage implements StorageAdapter {
  Map<String, dynamic> config = {'customKey': 'kept'};

  /// Purpose: Unused by these tests.
  /// Inputs: None. Returns: Never. Side effects: Throws.
  /// Notes: None.
  @override
  Future<Directory> getAppDir() => throw UnimplementedError();

  /// Purpose: Return a copy of the in-memory config.
  /// Inputs: None. Returns: Config map. Side effects: None.
  /// Notes: None.
  @override
  Future<Map<String, dynamic>> readConfig() async => Map.of(config);

  /// Purpose: Replace the in-memory config.
  /// Inputs: [value]. Returns: None. Side effects: Mutates [config].
  /// Notes: None.
  @override
  Future<void> writeConfig(Map<String, dynamic> value) async =>
      config = Map.of(value);
}

/// Purpose: Verify acknowledgement decisions, status and persistence.
/// Inputs: None. Returns: None. Side effects: Registers tests.
/// Notes: Pure logic plus an in-memory adapter.
void main() {
  final at = DateTime.utc(2026, 10, 6, 12);

  WebDavPrivacyAcknowledgement ack(int v) =>
      WebDavPrivacyAcknowledgement(noticeVersion: v, acknowledgedAt: at);

  test('needsAcknowledgement compares against the current version', () {
    expect(needsAcknowledgement(null, 1), isTrue);
    expect(needsAcknowledgement(ack(1), 1), isFalse);
    expect(needsAcknowledgement(ack(1), 2), isTrue);
    expect(needsAcknowledgement(ack(3), 2), isFalse);
  });

  test('status distinguishes first enable from paused existing sync', () {
    final cases = [
      (false, null, WebDavPrivacyStatus.firstEnable),
      (true, null, WebDavPrivacyStatus.syncPaused),
      (true, ack(1), WebDavPrivacyStatus.syncPaused),
      (false, ack(2), WebDavPrivacyStatus.acknowledged),
      (true, ack(2), WebDavPrivacyStatus.acknowledged),
    ];
    for (final (configured, stored, expected) in cases) {
      expect(
        webDavPrivacyStatus(
          syncConfigured: configured,
          stored: stored,
          currentVersion: 2,
        ),
        expected,
        reason: 'configured=$configured stored=${stored?.noticeVersion}',
      );
    }
  });

  test('records round-trip in UTC and preserve unknown fields', () {
    final parsed = WebDavPrivacyAcknowledgement.tryParse({
      'noticeVersion': 2,
      'acknowledgedAt': '2026-10-06T21:00:00+09:00',
      'future': 'x',
    })!;
    expect(parsed.noticeVersion, 2);
    expect(parsed.acknowledgedAt, at);
    expect(parsed.acknowledgedAt.isUtc, isTrue);
    expect(parsed.toJson(), {
      'future': 'x',
      'noticeVersion': 2,
      'acknowledgedAt': '2026-10-06T12:00:00.000Z',
    });
  });

  test('malformed records count as absent', () {
    for (final bad in [
      null,
      'text',
      <String, dynamic>{},
      {'noticeVersion': '1', 'acknowledgedAt': '2026-10-06T00:00:00Z'},
      {'noticeVersion': 1, 'acknowledgedAt': 'not a date'},
    ]) {
      expect(
        WebDavPrivacyAcknowledgement.tryParse(bad),
        isNull,
        reason: '$bad',
      );
    }
  });

  test('storage-config store keeps other keys and can be cleared', () async {
    final storage = _MemoryStorage();
    final store = WebDavPrivacyAcknowledgementStore.storageConfig(storage);
    expect(await store.load(), isNull);

    await store.acknowledge(3, now: at);
    expect(storage.config['customKey'], 'kept');
    expect(storage.config[webDavPrivacyAcknowledgementKey], {
      'noticeVersion': 3,
      'acknowledgedAt': '2026-10-06T12:00:00.000Z',
    });
    expect((await store.load())!.noticeVersion, 3);

    await store.clear();
    expect(
      storage.config.containsKey(webDavPrivacyAcknowledgementKey),
      isFalse,
    );
    expect(storage.config['customKey'], 'kept');
  });

  test('callback store forwards reads and writes', () async {
    Map<String, dynamic>? saved;
    final store = WebDavPrivacyAcknowledgementStore(
      read: () async => saved,
      write: (json) async => saved = json,
    );
    final record = await store.acknowledge(1, now: at);
    expect(saved, record.toJson());
    expect(needsAcknowledgement(await store.load(), 1), isFalse);
  });
}
