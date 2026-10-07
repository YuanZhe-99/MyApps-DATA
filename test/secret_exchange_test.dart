// Tests for the generic API-key secret channel: the secrets document and its
// per-key merge, the namespaced local SecretStore, and SecretExchange against
// the in-memory FakeWebDAVServer. Ported from MyTranscribe's
// secrets_sync_test.dart and extended (namespaces, force modes, byte
// compatibility, typed I/O errors, structural exclusion from backup and ZIP).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

import 'golden/fake_webdav_server.dart';

const _fileName = 'transcribe_secrets.json';
const _remotePath = '/MyTranscribe';
const _remoteFile = '/dav$_remotePath/$_fileName';

class _TestStorage implements StorageAdapter {
  _TestStorage(this.directory);

  final Directory directory;

  @override
  Future<Directory> getAppDir() async => directory;

  @override
  Future<Map<String, dynamic>> readConfig() async => {};

  @override
  Future<void> writeConfig(Map<String, dynamic> config) async {}
}

/// Wraps the fake server to record requests and misbehave on demand.
class _Hooked extends http.BaseClient {
  _Hooked(this.inner);

  final FakeWebDAVServer inner;
  final List<http.BaseRequest> requests = [];

  /// Runs once, just before the first PUT reaches the server.
  Future<void> Function()? beforePut;

  /// Every GET after the first fails at the transport.
  bool failLaterGets = false;

  /// Every request fails at the transport.
  bool offline = false;

  int _gets = 0;

  List<http.BaseRequest> get puts =>
      requests.where((r) => r.method == 'PUT').toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    if (request.method == 'GET') {
      _gets++;
      if (failLaterGets && _gets >= 2) {
        throw http.ClientException('connection dropped');
      }
    }
    if (request.method == 'PUT' && beforePut != null) {
      final hook = beforePut!;
      beforePut = null;
      await hook();
    }
    return inner.send(request);
  }
}

void main() {
  late Directory root;
  late FakeWebDAVServer server;
  late _Hooked hooked;
  late SecretStore store;
  late int savedCount;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('myapps_secrets_');
    server = FakeWebDAVServer();
    hooked = _Hooked(server);
    savedCount = 0;
    store = SecretStore(
      storage: _TestStorage(root),
      fileName: _fileName,
      namespaces: {'provider'},
      onSaved: () => savedCount++,
    );
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  WebDAVConfig config(String url) => WebDAVConfig(
    serverUrl: url,
    username: 'user',
    password: 'pass',
    remotePath: _remotePath,
  );

  SecretExchange exchanger([SecretStore? s]) => SecretExchange(
    store: s ?? store,
    clientFactory: (c) =>
        WebDavClient(c, httpClient: hooked, retryDelay: Duration.zero),
  );

  Future<SecretExchangeOutcome> exchange(
    String url, {
    List<String> trusted = const [],
    SecretExchangeMode mode = SecretExchangeMode.sync,
  }) => exchanger().exchange(config(url), trustedHosts: trusted, mode: mode);

  const https = 'https://cloud.example.com/dav';

  void remoteHas(String id, String? key, DateTime at) {
    server.seed(
      _remoteFile,
      encodeSecretsDocument(
        SecretsDocument(
          keys: {id: SecretEntry(apiKey: key, updatedAt: at)},
        ),
      ),
    );
  }

  File localFile() => File(p.join(root.path, _fileName));

  group('SecretsDocument', () {
    test('reads and re-encodes a MyTranscribe file byte-identically', () {
      const legacy =
          '{\n'
          '  "version": 1,\n'
          '  "keys": {\n'
          '    "provider:old": {\n'
          '      "apiKey": null,\n'
          '      "updatedAt": "2026-09-06T00:00:00.000Z"\n'
          '    },\n'
          '    "provider:openai": {\n'
          '      "apiKey": "sk-a",\n'
          '      "updatedAt": "2026-09-05T10:00:00.000Z"\n'
          '    }\n'
          '  }\n'
          '}';
      final doc = SecretsDocument.fromJson(
        jsonDecode(legacy) as Map<String, dynamic>,
      );
      expect(encodeSecretsDocument(doc), legacy);
      expect(doc.keyFor('provider:openai'), 'sk-a');
      expect(doc.keyFor('provider:old'), isNull);
      expect(doc.keys['provider:old']!.apiKey, isNull);
    });

    test('preserves unknown top-level and entry fields', () {
      final doc = SecretsDocument.fromJson({
        'version': 1,
        'futureTop': {'a': 1},
        'keys': {
          'provider:x': {
            'apiKey': 'k',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'label': 'work',
          },
        },
      });
      final json = doc.toJson();
      expect(json['futureTop'], {'a': 1});
      expect((json['keys'] as Map)['provider:x']['label'], 'work');
      final updated = doc.withKey(
        'provider:x',
        'k2',
        now: DateTime.utc(2026, 2),
      );
      expect((updated.toJson()['keys'] as Map)['provider:x']['label'], 'work');
    });

    test('a wrong-typed keys value and bad entries read as empty', () {
      expect(SecretsDocument.fromJson({'keys': 'nope'}).keys, isEmpty);
      expect(
        SecretsDocument.fromJson({
          'keys': {'a': 1, 'b': 'x'},
        }).keys,
        isEmpty,
      );
    });

    test('a damaged timestamp loses to any real one', () {
      final damaged = SecretsDocument.fromJson({
        'keys': {
          'provider:x': {'apiKey': 'bad', 'updatedAt': 'garbage'},
        },
      });
      final real = SecretsDocument(
        keys: {
          'provider:x': SecretEntry(
            apiKey: 'good',
            updatedAt: DateTime.utc(2000),
          ),
        },
      );
      expect(mergeSecretsDocuments(damaged, real).keyFor('provider:x'), 'good');
      expect(mergeSecretsDocuments(real, damaged).keyFor('provider:x'), 'good');
    });

    test('withKey trims, and blank clears to a tombstone', () {
      final doc = SecretsDocument()
          .withKey('provider:x', '  sk  ', now: DateTime.utc(2026))
          .withKey('provider:y', '   ', now: DateTime.utc(2026));
      expect(doc.keyFor('provider:x'), 'sk');
      expect(doc.keys['provider:y']!.apiKey, isNull);
      expect(doc.configuredIds, {'provider:x'});
    });

    test('merge: newer wins, tie goes to remote, tombstones count', () {
      final t1 = DateTime.utc(2026, 1, 1);
      final t2 = DateTime.utc(2026, 1, 2);
      SecretsDocument one(String? key, DateTime at) => SecretsDocument(
        keys: {'provider:x': SecretEntry(apiKey: key, updatedAt: at)},
      );
      expect(
        mergeSecretsDocuments(one('a', t2), one('b', t1)).keyFor('provider:x'),
        'a',
      );
      expect(
        mergeSecretsDocuments(one('a', t1), one('b', t1)).keyFor('provider:x'),
        'b',
      );
      expect(
        mergeSecretsDocuments(one('a', t1), one(null, t2)).keyFor('provider:x'),
        isNull,
      );
    });

    test('encoding is sorted and stable', () {
      final a = SecretsDocument(
        keys: {
          'provider:b': SecretEntry(apiKey: '1', updatedAt: DateTime.utc(2026)),
          'provider:a': SecretEntry(apiKey: '2', updatedAt: DateTime.utc(2026)),
        },
      );
      final b = SecretsDocument(
        keys: {
          'provider:a': SecretEntry(apiKey: '2', updatedAt: DateTime.utc(2026)),
          'provider:b': SecretEntry(apiKey: '1', updatedAt: DateTime.utc(2026)),
        },
      );
      expect(encodeSecretsDocument(a), encodeSecretsDocument(b));
      expect(
        encodeSecretsDocument(a).indexOf('provider:a'),
        lessThan(encodeSecretsDocument(a).indexOf('provider:b')),
      );
    });
  });

  group('SecretStore', () {
    test('rejects path-like file names and bad namespaces', () {
      final storage = _TestStorage(root);
      expect(
        () => SecretStore(storage: storage, fileName: 'a/b', namespaces: {'x'}),
        throwsArgumentError,
      );
      expect(
        () => SecretStore(storage: storage, fileName: ' ', namespaces: {'x'}),
        throwsArgumentError,
      );
      expect(
        () => SecretStore(storage: storage, fileName: 'f', namespaces: {}),
        throwsArgumentError,
      );
      expect(
        () => SecretStore(storage: storage, fileName: 'f', namespaces: {'a:b'}),
        throwsArgumentError,
      );
    });

    test('an app only reads and writes its own namespaces', () async {
      await store.setKey('provider:openai', 'sk-mine');
      final other = SecretStore(
        storage: _TestStorage(root),
        fileName: _fileName,
        namespaces: {'llm'},
      );
      await other.setKey('llm:local', 'sk-other');

      expect(store.ownsId('provider:openai'), isTrue);
      expect(store.ownsId('llm:local'), isFalse);
      expect(store.ownsId('provider:'), isFalse);
      expect(store.ownsId('openai'), isFalse);
      expect(() => store.keyFor('llm:local'), throwsArgumentError);
      expect(() => store.setKey('llm:local', 'x'), throwsArgumentError);
      expect(await store.configuredIds(), {'provider:openai'});
      expect(await other.configuredIds(), {'llm:local'});
      // Both writes share one file and one lock, so neither is lost.
      expect(await store.keyFor('provider:openai'), 'sk-mine');
      expect(await other.keyFor('llm:local'), 'sk-other');
    });

    test('setKey notifies, saveQuiet does not', () async {
      await store.setKey('provider:a', 'k');
      expect(savedCount, 1);
      await store.saveQuiet(await store.load());
      expect(savedCount, 1);
    });

    test('setKey stamps updatedAt in UTC', () async {
      final clocked = SecretStore(
        storage: _TestStorage(root),
        fileName: _fileName,
        namespaces: {'provider'},
        clock: () => DateTime.utc(2026, 10, 6, 10, 15),
      );
      await clocked.setKey('provider:a', 'k');
      final raw = localFile().readAsStringSync();
      expect(raw, contains('"updatedAt": "2026-10-06T10:15:00.000Z"'));
    });

    test('clearing writes a tombstone', () async {
      await store.setKey('provider:a', 'k');
      await store.setKey('provider:a', null);
      final doc = await store.load();
      expect(doc.keys.containsKey('provider:a'), isTrue);
      expect(doc.keyFor('provider:a'), isNull);
    });

    test('concurrent setKey calls are all kept', () async {
      await Future.wait([
        store.setKey('provider:a', 'sk-a'),
        store.setKey('provider:b', 'sk-b'),
        store.setKey('provider:c', 'sk-c'),
      ]);
      final doc = await store.load();
      expect(doc.configuredIds, {'provider:a', 'provider:b', 'provider:c'});
    });

    test('an unparseable file is set aside with a UTC stamp', () async {
      final clocked = SecretStore(
        storage: _TestStorage(root),
        fileName: _fileName,
        namespaces: {'provider'},
        clock: () => DateTime.utc(2026, 10, 6, 10, 15, 0, 123, 456),
      );
      localFile().writeAsStringSync('{ not json');
      await clocked.setKey('provider:a', 'k');
      final aside = File(
        p.join(root.path, '$_fileName.unreadable-20261006T101500123456Z'),
      );
      expect(aside.readAsStringSync(), '{ not json');
      expect(await clocked.keyFor('provider:a'), 'k');
    });

    test('non-object JSON and invalid UTF-8 are bad content too', () async {
      localFile().writeAsStringSync('[1, 2]');
      expect((await store.withLock(store.loadForWrite)).keys, isEmpty);
      localFile().writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect((await store.withLock(store.loadForWrite)).keys, isEmpty);
      final aside = root.listSync().whereType<File>().where(
        (f) => p.basename(f.path).contains('.unreadable-'),
      );
      expect(aside.length, 2);
    });

    test('a blank file reads as empty and is not set aside', () async {
      localFile().writeAsStringSync('  \n');
      expect((await store.withLock(store.loadForWrite)).keys, isEmpty);
      expect(localFile().existsSync(), isTrue);
    });

    test(
      'an I/O error is typed, not bad content, and changes nothing',
      () async {
        // A directory where the file should be cannot be read as a file.
        Directory(p.join(root.path, _fileName)).createSync();
        await expectLater(
          store.setKey('provider:a', 'k'),
          throwsA(isA<SecretsUnreadableException>()),
        );
        await expectLater(
          store.setKey('provider:a', 'k'),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          root.listSync().where((e) => e.path.contains('.unreadable-')),
          isEmpty,
        );
        expect(await store.load(), isA<SecretsDocument>());
      },
    );

    test(
      'an unreadable file (permissions) is typed and left in place',
      () async {
        await store.setKey('provider:a', 'k');
        final before = localFile().readAsStringSync();
        await Process.run('chmod', ['000', localFile().path]);
        try {
          final bypassed = await localFile().readAsString().then(
            (_) => true,
            onError: (_) => false,
          );
          if (bypassed) {
            markTestSkipped('permissions do not apply to this user');
            return;
          }
          await expectLater(
            store.setKey('provider:a', 'other'),
            throwsA(isA<SecretsUnreadableException>()),
          );
          expect(
            root.listSync().where((e) => e.path.contains('.unreadable-')),
            isEmpty,
          );
        } finally {
          await Process.run('chmod', ['600', localFile().path]);
        }
        expect(localFile().readAsStringSync(), before);
      },
      skip: Platform.isWindows ? 'chmod is POSIX-only' : false,
    );

    test('deleteAll removes the file', () async {
      await store.setKey('provider:a', 'k');
      await store.deleteAll();
      expect(localFile().existsSync(), isFalse);
    });

    test('is never picked up by backups or ZIP exports', () async {
      DataModule module(String name) => DataModule(
        fileName: name,
        moduleId: name,
        validate: (raw) => jsonDecode(raw),
        merge:
            ({
              required String localJson,
              required String remoteJson,
              required String? baseJson,
              required bool autoResolve,
            }) => ModuleMergeOutcome(mergedJson: remoteJson),
      );
      final registry = ModuleRegistry([module('settings.json')]);
      File(p.join(root.path, 'settings.json')).writeAsStringSync('{}');
      await store.setKey('provider:a', 'sk-should-not-leak');

      final backup = await BackupEngine(
        storage: _TestStorage(root),
        modules: registry,
        defaultRemotePath: _remotePath,
      ).createBackup();
      expect(backup!.readAsStringSync(), isNot(contains('sk-should-not')));

      final dest = await Directory.systemTemp.createTemp('myapps_zip_');
      try {
        final zipPath = await ZipTransfer(
          storage: _TestStorage(root),
          modules: registry,
          archiveNamePrefix: 'x_',
        ).exportZip(dest.path);
        final archive = ZipDecoder().decodeBytes(
          File(zipPath!).readAsBytesSync(),
        );
        expect(archive.files.map((f) => f.name), isNot(contains(_fileName)));
      } finally {
        await dest.delete(recursive: true);
      }
    });
  });

  group('an endpoint a key must not travel to', () {
    test('is refused and nothing is sent or fetched', () async {
      await store.setKey('provider:openai', 'sk-secret');
      for (final mode in SecretExchangeMode.values) {
        final outcome = await exchange(
          'http://dav.example.com/remote.php',
          mode: mode,
        );
        expect(outcome.status, SecretExchangeStatus.skippedInsecure);
        expect(outcome.reason, EndpointReason.deniedPublicHttp);
      }
      expect(hooked.requests, isEmpty, reason: 'no request in any direction');
    });

    test('leaves the local key exactly as it was', () async {
      await store.setKey('provider:openai', 'sk-secret');
      final before = localFile().readAsStringSync();
      await exchange('http://dav.example.com/remote.php');
      expect(localFile().readAsStringSync(), before);
    });

    test('names the rule that refused it', () async {
      expect(
        (await exchange('ftp://dav.example.com')).reason,
        EndpointReason.deniedScheme,
      );
      expect((await exchange('   ')).reason, EndpointReason.deniedUnparseable);
    });
  });

  group('an endpoint a key may travel to', () {
    test('uploads a key the server does not have, create-only', () async {
      await store.setKey('provider:openai', 'sk-secret');
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.reason, EndpointReason.https);
      expect(outcome.uploaded, isTrue);
      expect(outcome.keyCount, 1);
      expect(hooked.puts, hasLength(1));
      expect(hooked.puts.single.headers['If-None-Match'], '*');
      expect(server.readText(_remoteFile), localFile().readAsStringSync());
    });

    test('takes a key this device does not have', () async {
      remoteHas('provider:openrouter', 'sk-remote', DateTime.utc(2026, 9, 5));
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.downloaded, isTrue);
      expect(outcome.uploaded, isFalse);
      expect(await store.keyFor('provider:openrouter'), 'sk-remote');
      expect(savedCount, 0, reason: 'an exchange write is quiet');
    });

    test('keeps the newer of two keys for the same id', () async {
      await store.setKey('provider:openai', 'sk-old');
      remoteHas(
        'provider:openai',
        'sk-new',
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      await exchange(https);
      expect(await store.keyFor('provider:openai'), 'sk-new');
    });

    test('a newer local key is uploaded over an older remote', () async {
      remoteHas('provider:openai', 'sk-old', DateTime.utc(2020));
      await store.setKey('provider:openai', 'sk-new');
      final outcome = await exchange(https);
      expect(outcome.uploaded, isTrue);
      expect(server.readText(_remoteFile), contains('sk-new'));
    });

    test('a deletion travels rather than coming back', () async {
      await store.setKey('provider:openai', 'sk-old');
      remoteHas(
        'provider:openai',
        null,
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      await exchange(https);
      expect(await store.keyFor('provider:openai'), isNull);
    });

    test('sends nothing when both sides already agree', () async {
      await store.setKey('provider:openai', 'sk-secret');
      await exchange(https);
      final putsAfterFirst = hooked.puts.length;
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.uploaded, isFalse);
      expect(outcome.downloaded, isFalse);
      expect(hooked.puts, hasLength(putsAfterFirst));
    });

    test('does nothing at all when nobody has a key', () async {
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.nothingToDo);
      expect(hooked.puts, isEmpty);
      expect(localFile().existsSync(), isFalse);
    });

    test('LAN, Tailscale and trusted plain HTTP are allowed', () async {
      await store.setKey('provider:openai', 'sk-secret');
      expect(
        (await exchange('http://192.168.1.20:5005/dav')).reason,
        EndpointReason.privateIpv4,
      );
      expect(
        (await exchange('http://nas.tailnet-example.ts.net/dav')).status,
        SecretExchangeStatus.synced,
      );
      final trusted = await exchange(
        'http://dav.example.com/dav',
        trusted: ['dav.example.com'],
      );
      expect(trusted.status, SecretExchangeStatus.synced);
      expect(trusted.reason, EndpointReason.trustedHost);
    });

    test('another namespace on the same file travels too', () async {
      // The file is one per app; namespaces restrict the API, not the file.
      remoteHas('llm:local', 'sk-llm', DateTime.utc(2026));
      await store.setKey('provider:openai', 'sk-mine');
      final outcome = await exchange(https);
      expect(outcome.keyCount, 1);
      final doc = await store.load();
      expect(doc.keyFor('llm:local'), 'sk-llm');
      expect(await store.configuredIds(), {'provider:openai'});
    });

    test('preserves unknown remote fields on upload', () async {
      server.seed(
        _remoteFile,
        jsonEncode({
          'version': 1,
          'futureTop': true,
          'keys': {
            'provider:x': {
              'apiKey': 'k',
              'updatedAt': '2026-01-01T00:00:00.000Z',
              'label': 'work',
            },
          },
        }),
      );
      await store.setKey('provider:y', 'k2');
      await exchange(https);
      final remote = jsonDecode(server.readText(_remoteFile)!) as Map;
      expect(remote['futureTop'], true);
      expect(remote['keys']['provider:x']['label'], 'work');
    });
  });

  group('two devices writing at once', () {
    test('sends the entity tag it read', () async {
      await store.setKey('provider:openai', 'sk-mine');
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      final etag = server.files[_remoteFile]!.etag;
      await exchange(https);
      expect(hooked.puts.single.headers['If-Match'], etag);
    });

    test('the loser re-reads and merges rather than overwriting', () async {
      await store.setKey('provider:openai', 'sk-mine');
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      // Another device writes between this one's read and its write.
      hooked.beforePut = () async => server.seed(
        _remoteFile,
        encodeSecretsDocument(
          SecretsDocument(
            keys: {
              'provider:openrouter': SecretEntry(
                apiKey: 'sk-theirs',
                updatedAt: DateTime.utc(2026),
              ),
              'provider:third': SecretEntry(
                apiKey: 'sk-third',
                updatedAt: DateTime.utc(2026),
              ),
            },
          ),
        ),
      );

      final outcome = await exchange(https);

      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.uploaded, isTrue);
      expect(hooked.puts, hasLength(2));
      final remote = server.readText(_remoteFile)!;
      for (final k in ['sk-mine', 'sk-theirs', 'sk-third']) {
        expect(remote, contains(k));
      }
      expect(await store.keyFor('provider:third'), 'sk-third');
    });

    test(
      'a create-only race re-reads the file the other side created',
      () async {
        await store.setKey('provider:openai', 'sk-mine');
        hooked.beforePut = () async =>
            remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
        final outcome = await exchange(https);
        expect(outcome.status, SecretExchangeStatus.synced);
        expect(hooked.puts.last.headers['If-Match'], isNotNull);
        final remote = server.readText(_remoteFile)!;
        expect(remote, contains('sk-mine'));
        expect(remote, contains('sk-theirs'));
      },
    );

    test('a key typed during the upload survives the re-merge', () async {
      await store.setKey('provider:openai', 'sk-mine');
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      hooked.beforePut = () async {
        await store.setKey('provider:local', 'sk-typed');
        remoteHas('provider:openrouter', 'sk-theirs2', DateTime.utc(2026, 2));
      };

      final outcome = await exchange(https);

      expect(outcome.status, SecretExchangeStatus.synced);
      expect(await store.keyFor('provider:local'), 'sk-typed');
      expect(await store.keyFor('provider:openai'), 'sk-mine');
      expect(await store.keyFor('provider:openrouter'), 'sk-theirs2');
      expect(server.readText(_remoteFile), contains('sk-typed'));
    });

    test('a failed re-read fails and uploads nothing more', () async {
      await store.setKey('provider:openai', 'sk-mine');
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      hooked.beforePut = () async =>
          remoteHas('provider:other', 'sk-other', DateTime.utc(2026));
      hooked.failLaterGets = true;
      final failedOutcome = await exchange(https);
      final remoteAfter = server.readText(_remoteFile);

      expect(failedOutcome.status, SecretExchangeStatus.failed);
      expect(failedOutcome.error, isNotNull);
      expect(hooked.puts, hasLength(1), reason: 'only the refused PUT');
      expect(remoteAfter, contains('sk-other'));
      expect(remoteAfter, isNot(contains('sk-mine')));
      expect(await store.keyFor('provider:openai'), 'sk-mine');
    });

    test('a second 412 fails rather than looping', () async {
      await store.setKey('provider:openai', 'sk-mine');
      server.injectFault(
        (method, path) => method == 'PUT',
        () => http.StreamedResponse(Stream.value(utf8.encode('no')), 412),
      );
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.failed);
      expect(hooked.puts, hasLength(2));
    });
  });

  group('when the server misbehaves', () {
    test('an unreachable server is reported, not thrown', () async {
      await store.setKey('provider:openai', 'sk-secret');
      final before = localFile().readAsStringSync();
      hooked.offline = true;
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.failed);
      expect(outcome.error, isNotNull);
      expect(localFile().readAsStringSync(), before);
    });

    test('a remote file that does not parse is treated as absent', () async {
      await store.setKey('provider:openai', 'sk-secret');
      server.seed(_remoteFile, 'not json at all');
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(server.readText(_remoteFile), contains('sk-secret'));
    });

    test('a failed upload is reported', () async {
      await store.setKey('provider:openai', 'sk-secret');
      server.injectFault(
        (method, path) => method == 'PUT',
        () => http.StreamedResponse(Stream.value(utf8.encode('no')), 403),
      );
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.failed);
      expect(outcome.error, 'HTTP 403');
    });
  });

  group('the local file during an exchange', () {
    test(
      'an unparseable file is set aside and the exchange continues',
      () async {
        localFile().writeAsStringSync('{ this is not json');
        remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
        final outcome = await exchange(https);
        expect(outcome.status, SecretExchangeStatus.synced);
        expect(await store.keyFor('provider:openrouter'), 'sk-theirs');
        final aside = root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('$_fileName.unreadable-'))
            .toList();
        expect(aside, hasLength(1));
        expect(aside.single.readAsStringSync(), '{ this is not json');
      },
    );

    test('an I/O error fails the exchange and uploads nothing', () async {
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      Directory(p.join(root.path, _fileName)).createSync();
      final outcome = await exchange(https);
      expect(outcome.status, SecretExchangeStatus.failed);
      expect(hooked.puts, isEmpty);
      expect(
        root.listSync().where((e) => e.path.contains('.unreadable-')),
        isEmpty,
      );
    });

    test('no network call is made while the lock is held', () async {
      await store.setKey('provider:openai', 'sk-mine');
      remoteHas('provider:openrouter', 'sk-theirs', DateTime.utc(2026));
      var lockHeld = false;
      final probe = _LockProbe(server, () => lockHeld);
      final watched = SecretStore(
        storage: _TestStorage(root),
        fileName: _fileName,
        namespaces: {'provider'},
      );
      // Mark the lock as held for every action the exchange runs under it.
      final ex = SecretExchange(
        store: _WatchedStore(watched, (held) => lockHeld = held),
        clientFactory: (c) =>
            WebDavClient(c, httpClient: probe, retryDelay: Duration.zero),
      );
      final outcome = await ex.exchange(config(https));
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(probe.requestsWhileLocked, 0);
      expect(probe.requests, greaterThan(0));
    });
  });

  group('force modes', () {
    test('force upload replaces the remote without merging', () async {
      remoteHas(
        'provider:openai',
        'sk-remote-newer',
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      await store.setKey('provider:openai', 'sk-local');
      final before = localFile().readAsStringSync();
      final outcome = await exchange(
        https,
        mode: SecretExchangeMode.forceUpload,
      );
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.uploaded, isTrue);
      expect(outcome.downloaded, isFalse);
      expect(hooked.requests.where((r) => r.method == 'GET'), isEmpty);
      expect(hooked.puts.single.headers['If-Match'], isNull);
      expect(server.readText(_remoteFile), before);
      expect(localFile().readAsStringSync(), before);
    });

    test('force upload with no local keys uploads nothing', () async {
      remoteHas('provider:openai', 'sk-remote', DateTime.utc(2026));
      final outcome = await exchange(
        https,
        mode: SecretExchangeMode.forceUpload,
      );
      expect(outcome.status, SecretExchangeStatus.nothingToDo);
      expect(hooked.requests, isEmpty);
    });

    test('force download replaces the local copy without merging', () async {
      remoteHas('provider:openai', 'sk-remote-older', DateTime.utc(2020));
      await store.setKey('provider:openai', 'sk-local');
      await store.setKey('provider:only-local', 'x');
      final outcome = await exchange(
        https,
        mode: SecretExchangeMode.forceDownload,
      );
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.downloaded, isTrue);
      expect(outcome.uploaded, isFalse);
      expect(hooked.puts, isEmpty);
      expect(await store.keyFor('provider:openai'), 'sk-remote-older');
      expect(await store.keyFor('provider:only-local'), isNull);
    });

    test('force download with no remote file keeps the local copy', () async {
      await store.setKey('provider:openai', 'sk-local');
      final outcome = await exchange(
        https,
        mode: SecretExchangeMode.forceDownload,
      );
      expect(outcome.status, SecretExchangeStatus.synced);
      expect(outcome.downloaded, isFalse);
      expect(await store.keyFor('provider:openai'), 'sk-local');
    });

    test(
      'force download of an unparseable remote fails, writes nothing',
      () async {
        await store.setKey('provider:openai', 'sk-local');
        server.seed(_remoteFile, 'garbage');
        final outcome = await exchange(
          https,
          mode: SecretExchangeMode.forceDownload,
        );
        expect(outcome.status, SecretExchangeStatus.failed);
        expect(await store.keyFor('provider:openai'), 'sk-local');
      },
    );
  });
}

/// Counts requests made while the watched store's lock is held.
class _LockProbe extends http.BaseClient {
  _LockProbe(this.inner, this.isLocked);

  final FakeWebDAVServer inner;
  final bool Function() isLocked;
  int requests = 0;
  int requestsWhileLocked = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    if (isLocked()) requestsWhileLocked++;
    return inner.send(request);
  }
}

/// A store that reports when an action holds its lock.
class _WatchedStore extends SecretStore {
  _WatchedStore(SecretStore inner, this.onHeld)
    : super(
        storage: inner.storage,
        fileName: inner.fileName,
        namespaces: inner.namespaces,
      );

  final void Function(bool held) onHeld;

  @override
  Future<T> withLock<T>(Future<T> Function() action) =>
      super.withLock(() async {
        onHeld(true);
        try {
          return await action();
        } finally {
          onHeld(false);
        }
      });
}
