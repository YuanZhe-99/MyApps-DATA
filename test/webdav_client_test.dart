// P2.5 WebDAV client tests - exercises WebDAVConfig, WebDAVUploadLock,
// UploadSession, RemoteFile, and WebDavClient (verbs, auth, retry, remote lock
// primitives, heartbeat) against the in-memory FakeWebDAVServer.
//
// Feature-matrix coverage: §A1-A18 (config/transport), §B1-B11 (upload lock),
// §C-P1-P4 (PROPFIND parsing), §D1-D6 (retry/exception taxonomy).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_data/src/webdav/webdav_config.dart';
import 'package:myapps_data/src/webdav/upload_lock.dart';
import 'package:myapps_data/src/webdav/webdav_client.dart';

import 'golden/fake_webdav_server.dart';

/// Convenience server URL / remote path used across test groups.
const _serverUrl = 'https://x.test/dav/files/u';
const _remotePath = '/MyApp';
const _basePath = '/dav/files/u/MyApp';

/// Build a [WebDavClient] backed by [server] with instant retry delays.
WebDavClient _client(
  FakeWebDAVServer server, {
  WebDAVConfig? config,
  Duration? lockTtl,
  Duration? heartbeat,
  Duration? propfindTimeout,
}) => WebDavClient(
  config ??
      const WebDAVConfig(
        serverUrl: _serverUrl,
        username: 'u',
        password: 'p',
        remotePath: _remotePath,
      ),
  httpClient: server,
  retryDelay: Duration.zero,
  lockTtl: lockTtl ?? const Duration(seconds: 60),
  heartbeatInterval: heartbeat ?? const Duration(seconds: 20),
  propfindTimeout: propfindTimeout ?? const Duration(seconds: 15),
);

void main() {
  // ── WebDAVConfig ──

  group('WebDAVConfig', () {
    test('fields and defaults (§A1-A2)', () {
      const c = WebDAVConfig(
        serverUrl: 'https://s',
        username: 'u',
        password: 'p',
      );
      expect(c.serverUrl, 'https://s');
      expect(c.username, 'u');
      expect(c.password, 'p');
      expect(c.remotePath, ''); // package default (not per-app)
      expect(c.autoSync, false);
    });

    test('isConfigured checks credentials only (§A4)', () {
      expect(
        const WebDAVConfig(
          serverUrl: 's',
          username: 'u',
          password: 'p',
        ).isConfigured,
        true,
      );
      expect(
        const WebDAVConfig(
          serverUrl: '',
          username: 'u',
          password: 'p',
        ).isConfigured,
        false,
      );
      expect(
        const WebDAVConfig(
          serverUrl: 's',
          username: '',
          password: 'p',
        ).isConfigured,
        false,
      );
      expect(
        const WebDAVConfig(
          serverUrl: 's',
          username: 'u',
          password: '',
        ).isConfigured,
        false,
      );
    });

    test('copyWith updates autoSync only (§A4)', () {
      const c = WebDAVConfig(
        serverUrl: 's',
        username: 'u',
        password: 'p',
        remotePath: '/X',
      );
      final c2 = c.copyWith(autoSync: true);
      expect(c2.autoSync, true);
      expect(c2.serverUrl, 's');
      expect(c2.remotePath, '/X');
      // original unchanged
      expect(c.autoSync, false);
    });

    test('toJson / fromJson round-trip (§A4)', () {
      const c = WebDAVConfig(
        serverUrl: 'https://s',
        username: 'u',
        password: 'p',
        remotePath: '/MyApp',
        autoSync: true,
      );
      final json = c.toJson();
      expect(json['serverUrl'], 'https://s');
      expect(json['remotePath'], '/MyApp');
      expect(json['autoSync'], true);
      final c2 = WebDAVConfig.fromJson(json);
      expect(c2.serverUrl, c.serverUrl);
      expect(c2.username, c.username);
      expect(c2.password, c.password);
      expect(c2.remotePath, c.remotePath);
      expect(c2.autoSync, c.autoSync);
    });

    test('fromJson defaults missing fields to empty/false (§A4)', () {
      final c = WebDAVConfig.fromJson({});
      expect(c.serverUrl, '');
      expect(c.username, '');
      expect(c.password, '');
      expect(c.remotePath, '');
      expect(c.autoSync, false);
    });

    test('nextcloud factory constructs serverUrl (§A3)', () {
      final c = WebDAVConfig.nextcloud('cloud.example.com', 'alice', 'secret');
      expect(
        c.serverUrl,
        'https://cloud.example.com/remote.php/dav/files/alice',
      );
      expect(c.username, 'alice');
      expect(c.password, 'secret');
      expect(c.remotePath, ''); // package default
      expect(c.autoSync, false);
    });
  });

  // ── WebDAVUploadLock ──

  group('WebDAVUploadLock', () {
    test('fromJson / toJson round-trip (§B4)', () {
      final lock = WebDAVUploadLock(
        clientId: 'cid',
        token: 'tok',
        startedAt: DateTime.utc(2026, 7, 23, 0, 0, 0),
        updatedAt: DateTime.utc(2026, 7, 23, 0, 0, 30),
        ttlSeconds: 60,
      );
      final json = lock.toJson();
      expect(json['clientId'], 'cid');
      expect(json['token'], 'tok');
      expect(json['startedAt'], '2026-07-23T00:00:00.000Z');
      expect(json['updatedAt'], '2026-07-23T00:00:30.000Z');
      expect(json['ttlSeconds'], 60);

      final lock2 = WebDAVUploadLock.fromJson(json);
      expect(lock2.clientId, 'cid');
      expect(lock2.token, 'tok');
      expect(lock2.startedAt, lock.startedAt);
      expect(lock2.updatedAt, lock.updatedAt);
      expect(lock2.ttlSeconds, 60);
    });

    test('fromJson defaults ttlSeconds to 60 (§B5)', () {
      final lock = WebDAVUploadLock.fromJson({
        'clientId': 'c',
        'token': 't',
        'startedAt': '2026-07-23T00:00:00.000Z',
        'updatedAt': '2026-07-23T00:00:00.000Z',
      });
      expect(lock.ttlSeconds, defaultLockTtlSeconds);
      expect(lock.ttlSeconds, 60);
    });

    test('isExpired (§B11)', () {
      final updatedAt = DateTime.utc(2026, 7, 23, 0, 0, 0);
      final lock = WebDAVUploadLock(
        clientId: 'c',
        token: 't',
        startedAt: updatedAt,
        updatedAt: updatedAt,
        ttlSeconds: 60,
      );
      // 30s later - not expired
      expect(lock.isExpired(updatedAt.add(const Duration(seconds: 30))), false);
      // exactly 60s later - expired (>=)
      expect(lock.isExpired(updatedAt.add(const Duration(seconds: 60))), true);
      // 59s later - not expired
      expect(lock.isExpired(updatedAt.add(const Duration(seconds: 59))), false);
    });

    test('matches (§B7)', () {
      final now = DateTime.utc(2026, 7, 23);
      final lock = WebDAVUploadLock(
        clientId: 'cid',
        token: 'tok',
        startedAt: now,
        updatedAt: now,
        ttlSeconds: 60,
      );
      expect(lock.matches('cid', 'tok'), true);
      expect(lock.matches('cid', 'wrong'), false);
      expect(lock.matches('wrong', 'tok'), false);
    });

    test('refreshed keeps token and startedAt (§B)', () {
      final started = DateTime.utc(2026, 7, 23, 0, 0, 0);
      final lock = WebDAVUploadLock(
        clientId: 'cid',
        token: 'tok',
        startedAt: started,
        updatedAt: started,
        ttlSeconds: 60,
      );
      final refreshed = lock.refreshed(
        started.add(const Duration(seconds: 20)),
      );
      expect(refreshed.clientId, 'cid');
      expect(refreshed.token, 'tok');
      expect(refreshed.startedAt, started);
      expect(refreshed.updatedAt, started.add(const Duration(seconds: 20)));
      expect(refreshed.ttlSeconds, 60);
    });
  });

  // ── UploadSession ──

  test('UploadSession holds clientId and token', () {
    const session = UploadSession(clientId: 'cid', token: 'tok');
    expect(session.clientId, 'cid');
    expect(session.token, 'tok');
  });

  // ── RemoteFile ──

  group('RemoteFile', () {
    test('found carries content and etag (§D5)', () {
      const f = RemoteFile.found('hello', etag: '"v1"');
      expect(f.status, RemoteFileStatus.found);
      expect(f.content, 'hello');
      expect(f.etag, '"v1"');
      expect(f.error, isNull);
    });

    test('notFound (§D5)', () {
      const f = RemoteFile.notFound();
      expect(f.status, RemoteFileStatus.notFound);
      expect(f.content, isNull);
      expect(f.etag, isNull);
      expect(f.error, isNull);
    });

    test('failure carries error message (§D6)', () {
      const f = RemoteFile.failure('HTTP 500');
      expect(f.status, RemoteFileStatus.error);
      expect(f.content, isNull);
      expect(f.etag, isNull);
      expect(f.error, 'HTTP 500');
    });
  });

  // ── WebDavClient helpers ──

  group('WebDavClient URL / auth helpers', () {
    test(
      'remoteFileUrl strips trailing slash and ensures path slash (§A5)',
      () {
        final client = WebDavClient(
          const WebDAVConfig(
            serverUrl: 'https://s/',
            username: 'u',
            password: 'p',
            remotePath: '/MyApp',
          ),
        );
        expect(client.remoteFileUrl('data.json'), 'https://s/MyApp/data.json');
      },
    );

    test('remoteFileUrl handles no trailing slashes', () {
      final client = WebDavClient(
        const WebDAVConfig(
          serverUrl: 'https://s',
          username: 'u',
          password: 'p',
          remotePath: '/MyApp/',
        ),
      );
      expect(client.remoteFileUrl('data.json'), 'https://s/MyApp/data.json');
    });

    test('authHeaders produces Basic auth (§A6)', () {
      final client = WebDavClient(
        const WebDAVConfig(
          serverUrl: 'https://s',
          username: 'user',
          password: 'pass',
        ),
      );
      final h = client.authHeaders();
      expect(h['Authorization'], startsWith('Basic '));
      final decoded = utf8.decode(
        base64Decode(h['Authorization']!.substring(6)),
      );
      expect(decoded, 'user:pass');
    });

    test('strongEtag filters weak and null (§A)', () {
      expect(WebDavClient.strongEtag('"v1"'), '"v1"');
      expect(WebDavClient.strongEtag('W/"v1"'), isNull);
      expect(WebDavClient.strongEtag(null), isNull);
    });

    test('lockTtlSeconds derives from lockTtl', () {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        lockTtl: const Duration(seconds: 90),
      );
      expect(client.lockTtlSeconds, 90);
    });
  });

  // ── WebDavClient verbs ──

  group('WebDavClient.testConnection', () {
    test('returns true for 207 (collection exists) (§A9-A10)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/data.json', '{"ok":true}');
      final client = _client(server);
      expect(await client.testConnection(), true);
    });

    test(
      'returns true for 404 (server reachable, path absent) (§A10/C1)',
      () async {
        final server = FakeWebDAVServer();
        final client = _client(server);
        // No files seeded -> PROPFIND depth 0 returns 404
        expect(await client.testConnection(), true);
      },
    );

    test('returns false on transport error', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'PROPFIND',
        Faults.timeout(),
      );
      final client = _client(server);
      expect(await client.testConnection(), false);
    });
  });

  group('WebDavClient.ensureRemoteDir', () {
    test('sends MKCOL and swallows errors (§A11)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      await client.ensureRemoteDir(); // should not throw
      // MKCOL returns 201 in the fake (no files created, but no error)
    });

    test('swallows MKCOL failure', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'MKCOL',
        Faults.serverError(),
      );
      final client = _client(server);
      await client.ensureRemoteDir(); // should not throw
    });
  });

  group('WebDavClient.ensureRemoteSubDir', () {
    test('sends MKCOL for sub-directory (§A12)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      await client.ensureRemoteSubDir('images'); // should not throw
    });
  });

  group('WebDavClient.download', () {
    test('returns found with content and etag on 200 (§A15/D5)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/data.json', '{"items":[]}');
      final client = _client(server);
      final r = await client.download('data.json');
      expect(r.status, RemoteFileStatus.found);
      expect(r.content, '{"items":[]}');
      expect(r.etag, isNotNull);
    });

    test('returns notFound on 404 (§D5)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      final r = await client.download('missing.json');
      expect(r.status, RemoteFileStatus.notFound);
    });

    test('returns error on 403 (§D6)', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'GET' && path == '$_basePath/data.json',
        () =>
            http.StreamedResponse(Stream.value(utf8.encode('Forbidden')), 403),
      );
      final client = _client(server);
      final r = await client.download('data.json');
      expect(r.status, RemoteFileStatus.error);
      expect(r.error, 'HTTP 403');
    });

    test('retries on 500 then succeeds (§D1-D3)', () async {
      final server = FakeWebDAVServer();
      var callCount = 0;
      server.injectFault(
        (method, path) =>
            method == 'GET' &&
            path == '$_basePath/data.json' &&
            callCount++ < 1,
        Faults.serverError(),
      );
      server.seed('$_basePath/data.json', '{"v":1}');
      final client = _client(server);
      final r = await client.download('data.json');
      expect(r.status, RemoteFileStatus.found);
      expect(r.content, '{"v":1}');
    });
  });

  group('WebDavClient.upload', () {
    test('returns null error on success (§A13)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      final r = await client.upload('data.json', '{"v":1}');
      expect(r.is412, false);
      expect(r.error, isNull);
      expect(server.readText('$_basePath/data.json'), '{"v":1}');
    });

    test('returns is412 on precondition failure (§A13)', () async {
      final server = FakeWebDAVServer();
      // Seed a file so If-None-Match: * fails
      server.seed('$_basePath/data.json', '{"existing":true}');
      final client = _client(server);
      final r = await client.upload(
        'data.json',
        '{"v":2}',
        ifNoneMatchAll: true,
      );
      expect(r.is412, true);
      expect(r.error, 'conditional WebDAV PUT failed (HTTP 412)');
    });

    test('returns error on 403', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'PUT' && path == '$_basePath/data.json',
        () =>
            http.StreamedResponse(Stream.value(utf8.encode('Forbidden')), 403),
      );
      final client = _client(server);
      final r = await client.upload('data.json', '{"v":1}');
      expect(r.is412, false);
      expect(r.error, 'HTTP 403');
    });

    test('If-Match with correct etag succeeds', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/data.json', '{"old":true}');
      final existingEtag = server.files['$_basePath/data.json']!.etag;
      final client = _client(server);
      final r = await client.upload(
        'data.json',
        '{"new":true}',
        ifMatchEtag: existingEtag,
      );
      expect(r.error, isNull);
      expect(server.readText('$_basePath/data.json'), '{"new":true}');
    });

    test('If-Match with stale etag returns 412', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/data.json', '{"old":true}');
      final client = _client(server);
      final r = await client.upload(
        'data.json',
        '{"new":true}',
        ifMatchEtag: '"stale"',
      );
      expect(r.is412, true);
    });

    test('retries on 500 then succeeds (§D1-D3)', () async {
      final server = FakeWebDAVServer();
      var callCount = 0;
      server.injectFault(
        (method, path) =>
            method == 'PUT' &&
            path == '$_basePath/data.json' &&
            callCount++ < 1,
        Faults.serverError(),
      );
      final client = _client(server);
      final r = await client.upload('data.json', '{"v":1}');
      expect(r.error, isNull);
      expect(server.readText('$_basePath/data.json'), '{"v":1}');
    });

    test('retries: 0 means no retry on 500 (§D4 - lock writes)', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'PUT' && path == '$_basePath/.lock',
        Faults.serverError(),
      );
      final client = _client(server);
      // writeRemoteUploadLock uses retries: 0
      final lock = WebDAVUploadLock(
        clientId: 'c',
        token: 't',
        startedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        ttlSeconds: 60,
      );
      final r = await client.writeRemoteUploadLock(lock);
      expect(r.error, isNotNull);
      expect(r.is412, false);
    });
  });

  group('WebDavClient.uploadBytes', () {
    test('uploads binary content (§A14)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await client.uploadBytes('images/cover.jpg', bytes);
      expect(server.files['$_basePath/images/cover.jpg']?.bytes, bytes);
    });

    test('throws on non-2xx (§A14)', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'PUT' && path == '$_basePath/images/x.jpg',
        () =>
            http.StreamedResponse(Stream.value(utf8.encode('Forbidden')), 403),
      );
      final client = _client(server);
      expect(
        () => client.uploadBytes('images/x.jpg', Uint8List.fromList([1])),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('WebDavClient.downloadBytes', () {
    test('downloads binary content (§A16)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/images/cover.jpg', [10, 20, 30]);
      final client = _client(server);
      final bytes = await client.downloadBytes('images/cover.jpg');
      expect(bytes, [10, 20, 30]);
    });

    test('throws on non-200 (§A16)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      expect(
        () => client.downloadBytes('images/missing.jpg'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('WebDavClient.delete', () {
    test('deletes a remote file (§A17)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', '{"lock":true}');
      final client = _client(server);
      await client.delete('.lock');
      expect(server.exists('$_basePath/.lock'), false);
    });

    test('swallows error when file is missing (§A17)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      await client.delete('.lock'); // should not throw
    });

    test('supports If-Match etag', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', '{"lock":true}');
      final etag = server.files['$_basePath/.lock']!.etag;
      final client = _client(server);
      await client.delete('.lock', etag: etag);
      expect(server.exists('$_basePath/.lock'), false);
    });
  });

  group('WebDavClient.listSubDir', () {
    test('lists files in a sub-directory (§C-P1-P4)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/images/a.jpg', [1]);
      server.seed('$_basePath/images/b.jpg', [2]);
      final client = _client(server);
      final names = await client.listSubDir('images');
      expect(names, isNotNull);
      expect(names!, {'a.jpg', 'b.jpg'});
    });

    test('skips directory entries (§C-P2)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/images/sub/c.jpg', [3]);
      server.seed('$_basePath/images/d.jpg', [4]);
      final client = _client(server);
      final names = await client.listSubDir('images');
      expect(names, isNotNull);
      // 'sub' appears as a directory href (ends with /) -> skipped;
      // 'd.jpg' is a direct child -> included
      expect(names!, contains('d.jpg'));
      expect(names, isNot(contains('sub')));
    });

    test('returns null on non-207 (unknown state)', () async {
      final server = FakeWebDAVServer();
      // No files under images/ -> PROPFIND depth 1 returns 404
      final client = _client(server);
      final names = await client.listSubDir('images');
      expect(names, isNull);
    });

    test('parses prefixed hrefs (DAV: namespace) (§C-P1)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/images/x.png', [5]);
      final client = _client(server);
      final names = await client.listSubDir('images');
      expect(names, {'x.png'});
    });

    test('retries on 500 (§D1-D3)', () async {
      final server = FakeWebDAVServer();
      var callCount = 0;
      server.seed('$_basePath/images/a.jpg', [1]);
      server.injectFault(
        (method, path) =>
            method == 'PROPFIND' &&
            path == '$_basePath/images/' &&
            callCount++ < 1,
        Faults.serverError(),
      );
      final client = _client(server);
      final names = await client.listSubDir('images');
      expect(names, isNotNull);
      expect(names!, contains('a.jpg'));
    });
  });

  // ── Remote lock primitives ──

  group('WebDavClient.readRemoteUploadLock', () {
    test('parses an existing lock (§B4)', () async {
      final server = FakeWebDAVServer();
      final lockJson = jsonEncode({
        'clientId': 'cid',
        'token': 'tok',
        'startedAt': '2026-07-23T00:00:00.000Z',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'ttlSeconds': 60,
      });
      server.seed('$_basePath/.lock', lockJson);
      final client = _client(server);
      final r = await client.readRemoteUploadLock();
      expect(r.error, isNull);
      expect(r.lock, isNotNull);
      expect(r.lock!.clientId, 'cid');
      expect(r.lock!.token, 'tok');
      expect(r.etag, isNotNull); // strong etag from fake server
    });

    test('returns null lock when not found (§B)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      final r = await client.readRemoteUploadLock();
      expect(r.error, isNull);
      expect(r.lock, isNull);
      expect(r.etag, isNull);
    });

    test('returns null lock for malformed content (§B)', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', 'not json');
      final client = _client(server);
      final r = await client.readRemoteUploadLock();
      expect(r.error, isNull);
      expect(r.lock, isNull);
      expect(r.etag, isNotNull); // strong etag still present
    });

    test('returns error on transport failure (§D5)', () async {
      final server = FakeWebDAVServer();
      server.injectFault(
        (method, path) => method == 'GET' && path == '$_basePath/.lock',
        Faults.serverError(),
      );
      final client = _client(server);
      // 500 retried 2x then fails -> download returns error
      final r = await client.readRemoteUploadLock();
      expect(r.lock, isNull);
      expect(r.error, isNotNull);
    });
  });

  group('WebDavClient.writeRemoteUploadLock', () {
    test('writes a new lock (§B10)', () async {
      final server = FakeWebDAVServer();
      final client = _client(server);
      final lock = WebDAVUploadLock(
        clientId: 'cid',
        token: 'tok',
        startedAt: DateTime.utc(2026, 7, 23),
        updatedAt: DateTime.utc(2026, 7, 23),
        ttlSeconds: 60,
      );
      final r = await client.writeRemoteUploadLock(lock);
      expect(r.error, isNull);
      final stored = server.readText('$_basePath/.lock');
      expect(stored, isNotNull);
      expect(jsonDecode(stored!)['clientId'], 'cid');
    });

    test('returns 412 on If-None-Match conflict', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', '{"existing":true}');
      final client = _client(server);
      final lock = WebDAVUploadLock(
        clientId: 'cid',
        token: 'tok',
        startedAt: DateTime.utc(2026, 7, 23),
        updatedAt: DateTime.utc(2026, 7, 23),
        ttlSeconds: 60,
      );
      final r = await client.writeRemoteUploadLock(lock, ifNoneMatchAll: true);
      expect(r.is412, true);
    });
  });

  group('WebDavClient.deleteRemoteUploadLock', () {
    test('deletes the lock file', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', '{"lock":true}');
      final client = _client(server);
      await client.deleteRemoteUploadLock();
      expect(server.exists('$_basePath/.lock'), false);
    });

    test('accepts etag precondition', () async {
      final server = FakeWebDAVServer();
      server.seed('$_basePath/.lock', '{"lock":true}');
      final etag = server.files['$_basePath/.lock']!.etag;
      final client = _client(server);
      await client.deleteRemoteUploadLock(etag: etag);
      expect(server.exists('$_basePath/.lock'), false);
    });
  });

  // ── withRetry ──

  group('WebDavClient.withRetry', () {
    test('returns value on first success (§D1)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      final v = await client.withRetry(() async => 42);
      expect(v, 42);
    });

    test('retries on transient exception then succeeds (§D1-D2)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      var attempts = 0;
      final v = await client.withRetry(() async {
        attempts++;
        if (attempts < 2) throw TimeoutException('boom');
        return 42;
      });
      expect(v, 42);
      expect(attempts, 2);
    });

    test('does not retry on non-transient exception', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      var attempts = 0;
      expect(
        () => client.withRetry(() async {
          attempts++;
          throw Exception('non-transient');
        }),
        throwsA(isA<Exception>()),
      );
      // Give the future a chance to complete
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
    });

    test('retries on shouldRetry predicate (5xx) (§D3)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      var attempts = 0;
      final v = await client.withRetry(
        () async => attempts++ < 1
            ? (http.Response('srv', 500))
            : (http.Response('ok', 200)),
        shouldRetry: (r) => r.statusCode >= 500,
      );
      expect(v.statusCode, 200);
      expect(attempts, 2);
    });

    test('does not retry when retries is 0 (§D4)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      var attempts = 0;
      final v = await client.withRetry(
        () async {
          attempts++;
          return http.Response('srv', 500);
        },
        shouldRetry: (r) => r.statusCode >= 500,
        retries: 0,
      );
      expect(v.statusCode, 500);
      expect(attempts, 1);
    });

    test('gives up after max retries and rethrows (§D1)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        retryDelay: Duration.zero,
      );
      var attempts = 0;
      try {
        await client.withRetry(() async {
          attempts++;
          throw TimeoutException('always fails');
        });
      } on TimeoutException {
        // expected
      }
      expect(attempts, 3); // 1 initial + 2 retries
    });
  });

  // ── withLockHeartbeat ──

  group('WebDavClient.withLockHeartbeat', () {
    test(
      'calls refreshLock periodically and returns operation result (§B6)',
      () async {
        final client = WebDavClient(
          const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
          heartbeatInterval: const Duration(milliseconds: 20),
        );
        var refreshCount = 0;
        final result = await client.withLockHeartbeat(
          refreshLock: () async {
            refreshCount++;
          },
          operation: () async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return 'done';
          },
        );
        expect(result, 'done');
        // At least one heartbeat should have fired in 80ms with 20ms interval
        expect(refreshCount, greaterThanOrEqualTo(1));
      },
    );

    test('cancels timer when operation completes', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        heartbeatInterval: const Duration(milliseconds: 10),
      );
      var refreshCount = 0;
      await client.withLockHeartbeat(
        refreshLock: () async => refreshCount++,
        operation: () async => 42,
      );
      final countAfter = refreshCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refreshCount, countAfter); // no more refreshes after completion
    });

    test('swallows refreshLock errors (§B6)', () async {
      final client = WebDavClient(
        const WebDAVConfig(serverUrl: 's', username: 'u', password: 'p'),
        heartbeatInterval: const Duration(milliseconds: 10),
      );
      final result = await client.withLockHeartbeat(
        refreshLock: () async => throw Exception('refresh failed'),
        operation: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'ok';
        },
      );
      expect(result, 'ok'); // operation succeeded despite refresh errors
    });
  });
}
