// Spike: prove runWithClient intercepts BOTH inline `http.Client().send()` and
// top-level `http.get/put/delete` via the zone-scoped client factory, with zero
// app source changes. This is the mechanism the golden harness relies on.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
// runWithClient is declared in src/client.dart; the http.dart barrel's
// `export 'src/client.dart' hide zoneClient` does not surface it to consumers
// in this SDK, so import the declaration site directly (test-only code).
import 'package:http/src/client.dart' show runWithClient;

/// A minimal recording client that intercepts every request including streams.
class _RecordingClient extends http.BaseClient {
  final List<String> seen = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    seen.add('${request.method} ${request.url.path} bytes=${body.length}');
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  test(
    'runWithClient intercepts inline Client() and top-level calls',
    () async {
      final client = _RecordingClient();

      await runWithClient(() async {
        // Path 1: inline `http.Client().send(request)` (streaming, used by
        // testConnection / PROPFIND / MKCOL in the apps).
        final req = http.Request('PROPFIND', Uri.parse('https://x.test/dir/'));
        final streamed = await http.Client().send(req);
        expect(streamed.statusCode, 200);

        // Path 2: top-level `http.put(...)` (used by _upload/_uploadBytes).
        final put = await http.put(
          Uri.parse('https://x.test/a.json'),
          body: 'data',
        );
        expect(put.statusCode, 200);

        // Path 3: top-level `http.get(...)` (used by _download).
        final get = await http.get(Uri.parse('https://x.test/a.json'));
        expect(get.body, '{"ok":true}');
      }, () => client);

      expect(client.seen, [
        'PROPFIND /dir/ bytes=0',
        'PUT /a.json bytes=4',
        'GET /a.json bytes=0',
      ]);
    },
  );
}
