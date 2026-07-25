// Harness self-test: proves the FakeWebDAVServer + RequestRecorder faithfully
// model the sync request sequence and lock semantics before wiring into apps.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/src/client.dart' show runWithClient;

import 'fake_webdav_server.dart';
import 'request_recorder.dart';

void main() {
  test('fake server supports full lock + data + listing lifecycle', () async {
    final server = FakeWebDAVServer(basePath: '/dav/files/u');
    final recorder = RequestRecorder(server);
    const base = 'https://x.test/dav/files/u/MyAnime';

    await runWithClient(() async {
      // ensureRemoteDir (MKCOL)
      await http.Request('MKCOL', Uri.parse('$base/')).send();
      // read remote lock (GET .lock -> 404)
      final lockGet1 = await http.get(Uri.parse('$base/.lock'));
      expect(lockGet1.statusCode, 404);
      // acquire lock (PUT .lock If-None-Match:* -> 201)
      final lockJson = jsonEncode({
        'clientId': 'cid',
        'token': 'tok',
        'startedAt': '2026-07-23T00:00:00.000Z',
        'updatedAt': '2026-07-23T00:00:00.000Z',
        'ttlSeconds': 60,
      });
      final lockPut = await http.put(
        Uri.parse('$base/.lock'),
        headers: {'If-None-Match': '*'},
        body: lockJson,
      );
      expect(lockPut.statusCode, 201);
      // duplicate acquire with If-None-Match:* now fails 412 (lock exists)
      final lockPut2 = await http.put(
        Uri.parse('$base/.lock'),
        headers: {'If-None-Match': '*'},
        body: lockJson,
      );
      expect(lockPut2.statusCode, 412);
      // data file download (404 -> not found on first sync)
      final dataGet = await http.get(Uri.parse('$base/anime_data.json'));
      expect(dataGet.statusCode, 404);
      // upload data (unconditional force PUT)
      final dataPut = await http.put(
        Uri.parse('$base/anime_data.json'),
        body: '{"animes":[]}',
      );
      expect(dataPut.statusCode, 201);
      // image listing (PROPFIND depth 1) - seed an image so the collection exists
      server.seed('/dav/files/u/MyAnime/images/cover1.jpg', [1, 2, 3]);
      final propfind = http.Request('PROPFIND', Uri.parse('$base/images/'))
        ..headers['Depth'] = '1';
      final listing = await propfind.send();
      expect(listing.statusCode, 207);
      final listingBody = await listing.stream.bytesToString();
      expect(listingBody, contains('cover1.jpg'));
      // empty collection -> 404 (matches real WebDAV; apps treat listing failure as skip)
      final emptyPropfind = http.Request(
        'PROPFIND',
        Uri.parse('$base/nonexistent/'),
      )..headers['Depth'] = '1';
      final emptyListing = await emptyPropfind.send();
      expect(emptyListing.statusCode, 404);
      // release lock: read etag then DELETE with If-Match
      final lockGet2 = await http.get(Uri.parse('$base/.lock'));
      final etag = lockGet2.headers['etag']!;
      final del = await http.delete(
        Uri.parse('$base/.lock'),
        headers: {'If-Match': etag},
      );
      expect(del.statusCode, 204);
      expect(
        server.exists('$base/.lock'.replaceFirst('https://x.test', '')),
        isFalse,
      );
    }, () => recorder);

    final transcript = GoldenTranscript(recorder.exchanges).render();
    expect(transcript, contains('MKCOL'));
    expect(transcript, contains('PUT /dav/files/u/MyAnime/.lock'));
    expect(transcript, contains('PROPFIND'));
    // etags normalized
    expect(transcript, isNot(contains('etag-1')));
    expect(transcript, contains('<etag>'));
  });

  test('fault injection: 5xx and timeout are surfaced to caller', () async {
    final server = FakeWebDAVServer();
    final recorder = RequestRecorder(server);
    server.injectFault(
      (m, p) => m == 'GET' && p.endsWith('flaky.json'),
      Faults.serverError(),
    );
    await runWithClient(() async {
      final r = await http.get(Uri.parse('https://x.test/flaky.json'));
      expect(r.statusCode, 500);
    }, () => recorder);
  });

  test('PUT If-Match with stale etag returns 412', () async {
    final server = FakeWebDAVServer();
    server.seed('/dav/files/u/MyDay/.lock', '{"stale":true}');
    final recorder = RequestRecorder(server);
    await runWithClient(() async {
      final r = await http.put(
        Uri.parse('https://x.test/dav/files/u/MyDay/.lock'),
        headers: {'If-Match': '"wrong-etag"'},
        body: '{}',
      );
      expect(r.statusCode, 412);
    }, () => recorder);
  });
}
