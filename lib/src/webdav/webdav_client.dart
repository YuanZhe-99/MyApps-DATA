/// Purpose: Pure WebDAV transport client — verbs, auth, retry, remote lock
/// primitives, and heartbeat mechanism.  No local filesystem access.
/// Inputs: HTTP requests via `package:http`.
/// Returns: `RemoteFile`, upload results, lock states, and file listings.
/// Side effects: Performs network I/O; mutates remote `.lock` and data files.
/// Notes: This is the P2.5 deliverable (feature-matrix §A-§D, §B, §C).  All
/// timeouts, TTL, heartbeat, and retry backoff are injectable for tests with
/// defaults fixed to the apps' current values (I3).  The class performs
/// **no local filesystem I/O** — local lock-file management, client-ID
/// persistence, and base-snapshot storage belong to the sync engine (P2.6)
/// which composes these remote primitives with `StorageAdapter`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'upload_lock.dart';
import 'webdav_config.dart';

/// Outcome status of a remote file download attempt (feature-matrix §D5).
enum RemoteFileStatus { found, notFound, error }

/// Discriminated result of a remote file download.
///
/// Distinguishes "the file does not exist on the remote" (HTTP 404) from
/// transport/server failures (feature-matrix §D5-D6).  Only [notFound] may
/// trigger the upload-local-as-new sync path; treating [error] as "missing"
/// can overwrite remote data and cascade into cross-device record deletion.
class RemoteFile {
  /// Outcome of the download attempt.
  final RemoteFileStatus status;

  /// File content when [status] is [RemoteFileStatus.found].
  final String? content;

  /// Strong ETag from the response headers (may be null or absent).
  final String? etag;

  /// Error message when [status] is [RemoteFileStatus.error].
  final String? error;

  /// Purpose: Create a found result with downloaded content.
  /// Inputs: [content] file body; [etag] optional response header.
  /// Returns: A [RemoteFile] with [RemoteFileStatus.found].
  /// Side effects: None.
  /// Notes: None.
  const RemoteFile.found(String this.content, {this.etag})
    : status = RemoteFileStatus.found,
      error = null;

  /// Purpose: Create a not-found result for HTTP 404.
  /// Inputs: None.
  /// Returns: A [RemoteFile] with [RemoteFileStatus.notFound].
  /// Side effects: None.
  /// Notes: None.
  const RemoteFile.notFound()
    : status = RemoteFileStatus.notFound,
      content = null,
      etag = null,
      error = null;

  /// Purpose: Create an error result for any non-404 failure.
  /// Inputs: [error] message.
  /// Returns: A [RemoteFile] with [RemoteFileStatus.error].
  /// Side effects: None.
  /// Notes: None.
  const RemoteFile.failure(String this.error)
    : status = RemoteFileStatus.error,
      content = null,
      etag = null;
}

/// Pure WebDAV transport client (feature-matrix §A-§D).
///
/// Instance-based internally; app facades keep their static APIs by delegating
/// to a lazily-built [WebDavClient] singleton.
///
/// ## Verbs
/// [testConnection], [ensureRemoteDir], [ensureRemoteSubDir], [download],
/// [upload], [uploadBytes], [downloadBytes], [delete], [listSubDir].
///
/// ## Retry
/// [withRetry] implements the I3 retry policy (feature-matrix §D1-D4): max 2
/// extra attempts with 1s/2s backoff on socket/timeout/client/HTTP exceptions
/// and HTTP 5xx; 4xx never retried; lock writes pass `retries: 0`.
///
/// ## Remote lock primitives
/// [readRemoteUploadLock], [writeRemoteUploadLock], [deleteRemoteUploadLock].
/// These are remote-only; the sync engine (P2.6) composes them with local
/// lock-file persistence.
///
/// ## Heartbeat
/// [withLockHeartbeat] wraps a long transfer with periodic lock refresh so a
/// slow PUT cannot outlive the lock TTL (feature-matrix §B6).
class WebDavClient {
  /// Purpose: Create a WebDAV transport client.
  /// Inputs: [config] server/path/credentials; [httpClient] optional injected
  /// client (tests / zone-interception); [lockTtl], [heartbeatInterval],
  /// [propfindTimeout], [retryDelay] injectable timing knobs (defaults fixed,
  /// feature-matrix §B5/§B6/§A18/§D1).
  /// Returns: A new [WebDavClient].
  /// Side effects: None.
  /// Notes: When [httpClient] is null each call creates a fresh `http.Client()`
  /// (matching apps' lifecycle, feature-matrix §A8) which is never closed.
  /// When provided, the caller owns the client's lifecycle.
  WebDavClient(
    this.config, {
    http.Client? httpClient,
    this.lockTtl = const Duration(seconds: 60),
    this.heartbeatInterval = const Duration(seconds: 20),
    this.propfindTimeout = const Duration(seconds: 15),
    this.retryDelay = const Duration(seconds: 1),
  }) : _injectedClient = httpClient;

  /// WebDAV server/path/credentials.
  final WebDAVConfig config;

  /// Injected HTTP client (null = create per call, matching apps' §A8).
  final http.Client? _injectedClient;

  /// Remote lock TTL (feature-matrix §B5, default 60s).
  final Duration lockTtl;

  /// Heartbeat refresh interval (feature-matrix §B6, default 20s).
  final Duration heartbeatInterval;

  /// PROPFIND listing timeout (feature-matrix §A18/§C-P4, default 15s).
  final Duration propfindTimeout;

  /// Base retry backoff; actual delay = `retryDelay * attemptIndex`
  /// (feature-matrix §D1, default 1s → 1s then 2s).
  final Duration retryDelay;

  /// Lock TTL in seconds (derived from [lockTtl]).
  int get lockTtlSeconds => lockTtl.inSeconds;

  /// Remote `.lock` file name (feature-matrix §B1).
  static const lockFileName = '.lock';

  /// Purpose: Obtain an HTTP client for a single call.
  /// Inputs: None.
  /// Returns: The injected client or a fresh `http.Client()`.
  /// Side effects: May create a new `http.Client`.
  /// Notes: Internal helper.  When no client is injected a new client is
  /// created per call (matching apps' §A8) and never closed.
  http.Client _clientForCall() => _injectedClient ?? http.Client();

  // ── URL / auth helpers ──

  /// Purpose: Build the full remote URL for [fileName].
  /// Inputs: [fileName] remote file name or sub-path.
  /// Returns: Full URL string.
  /// Side effects: None.
  /// Notes: feature-matrix §A5.  Strips trailing `/` from `serverUrl`, ensures
  /// `remotePath` ends with `/`.  No URL-encoding (preserves apps' wire format).
  String remoteFileUrl(String fileName) {
    final base = config.serverUrl.endsWith('/')
        ? config.serverUrl.substring(0, config.serverUrl.length - 1)
        : config.serverUrl;
    final path = config.remotePath.endsWith('/')
        ? config.remotePath
        : '${config.remotePath}/';
    return '$base$path$fileName';
  }

  /// Purpose: Build HTTP Basic auth headers.
  /// Inputs: None.
  /// Returns: `Map<String, String>` with the `Authorization` header.
  /// Side effects: None.
  /// Notes: feature-matrix §A6 — identical Base64 encoding across all three
  /// apps.  No User-Agent is set (§A7 — adding one would change the wire
  /// format).
  Map<String, String> authHeaders() {
    final creds = base64Encode(
      utf8.encode('${config.username}:${config.password}'),
    );
    return {'Authorization': 'Basic $creds'};
  }

  /// Purpose: Return [etag] only when it is a strong ETag usable for lock
  /// preconditions.
  /// Inputs: [etag] from a download response, possibly null or weak (`W/...`).
  /// Returns: The strong ETag, or null when absent/weak.
  /// Side effects: None.
  /// Notes: Weak ETags must not be used in `.lock` `If-Match` preconditions
  /// (RFC 9110 strong comparison).
  static String? strongEtag(String? etag) {
    if (etag == null || etag.startsWith('W/')) return null;
    return etag;
  }

  // ── Retry ──

  /// Purpose: Retry a network operation on transient failures.
  /// Inputs: [attempt] closure; [shouldRetry] optional predicate on the
  /// successful result; [retries] extra attempts after the first (default 2).
  /// Returns: `Future<T>` — the last attempt's value, or rethrows its error.
  /// Side effects: Waits `retryDelay * 1` then `retryDelay * 2` between
  /// attempts.
  /// Notes: feature-matrix §D1-D4.  Retries on `SocketException`,
  /// `TimeoutException`, `http.ClientException`, `HttpException` and on
  /// `shouldRetry` (used for HTTP 5xx).  4xx results are never retried by
  /// callers.  Lock writes pass `retries: 0` (§D4).
  Future<T> withRetry<T>(
    Future<T> Function() attempt, {
    bool Function(T value)? shouldRetry,
    int retries = 2,
  }) async {
    var attemptIndex = 0;
    while (true) {
      try {
        final value = await attempt();
        if (attemptIndex < retries && (shouldRetry?.call(value) ?? false)) {
          attemptIndex += 1;
          await Future<void>.delayed(retryDelay * attemptIndex);
          continue;
        }
        return value;
      } on Object catch (e) {
        final transient =
            e is SocketException ||
            e is TimeoutException ||
            e is http.ClientException ||
            e is HttpException;
        if (!transient || attemptIndex >= retries) rethrow;
        attemptIndex += 1;
        await Future<void>.delayed(retryDelay * attemptIndex);
      }
    }
  }

  // ── Verbs ──

  /// Purpose: Test the WebDAV connection via PROPFIND Depth:0.
  /// Inputs: None.
  /// Returns: `true` when the server returns HTTP 207 or 404.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A9-§A10.  10s timeout (fixed).  Swallows all errors
  /// and returns `false`.  Both 207 (collection exists) and 404 (server
  /// reachable, path absent) count as "reachable" (§A10/C1).
  Future<bool> testConnection() async {
    try {
      final base = config.serverUrl.endsWith('/')
          ? config.serverUrl.substring(0, config.serverUrl.length - 1)
          : config.serverUrl;
      final url = Uri.parse('$base${config.remotePath}/');
      final request = http.Request('PROPFIND', url);
      request.headers.addAll(authHeaders());
      request.headers['Depth'] = '0';
      request.headers['Content-Type'] = 'application/xml';
      request.body =
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';

      final client = _clientForCall();
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      return streamed.statusCode == 207 || streamed.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// Purpose: Ensure the remote base directory exists via MKCOL.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A11.  10s timeout.  Swallows all errors including
  /// 405/409 when the directory already exists.
  Future<void> ensureRemoteDir() async {
    try {
      final base = config.serverUrl.endsWith('/')
          ? config.serverUrl.substring(0, config.serverUrl.length - 1)
          : config.serverUrl;
      final url = Uri.parse('$base${config.remotePath}/');
      final request = http.Request('MKCOL', url);
      request.headers.addAll(authHeaders());
      final client = _clientForCall();
      await client.send(request).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Purpose: Ensure a remote sub-directory exists via MKCOL.
  /// Inputs: [name] sub-directory name.
  /// Returns: None.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A12.  10s timeout.  Swallows all errors.  URL is
  /// built via [remoteFileUrl] (unified form — MyDevice already used this).
  Future<void> ensureRemoteSubDir(String name) async {
    try {
      final url = Uri.parse(remoteFileUrl('$name/'));
      final request = http.Request('MKCOL', url);
      request.headers.addAll(authHeaders());
      final client = _clientForCall();
      await client.send(request).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Purpose: Download a remote data file with a discriminated outcome.
  /// Inputs: [name] remote file name.
  /// Returns: [RemoteFile] — [RemoteFileStatus.found] with content/ETag on 200,
  /// [RemoteFileStatus.notFound] on 404, [RemoteFileStatus.error] on any other
  /// failure.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A15/§D5-§D6.  30s timeout.  Retries on 5xx.  Only a
  /// true 404 returns [RemoteFileStatus.notFound]; any other failure returns
  /// [RemoteFileStatus.error] so callers can abort that file's sync instead of
  /// overwriting an unreadable remote file.
  Future<RemoteFile> download(String name) async {
    try {
      final url = Uri.parse(remoteFileUrl(name));
      final client = _clientForCall();
      final response = await withRetry(
        () => client
            .get(url, headers: authHeaders())
            .timeout(const Duration(seconds: 30)),
        shouldRetry: (r) => r.statusCode >= 500,
      );
      if (response.statusCode == 200) {
        return RemoteFile.found(response.body, etag: response.headers['etag']);
      }
      if (response.statusCode == 404) return const RemoteFile.notFound();
      return RemoteFile.failure('HTTP ${response.statusCode}');
    } catch (e) {
      return RemoteFile.failure('$e');
    }
  }

  /// Purpose: Upload string content to a remote WebDAV path.
  /// Inputs: [name] remote file name; [content] string body; [ifMatchEtag]
  /// optional strong ETag for conditional PUT; [ifNoneMatchAll] create-only
  /// flag; [retries] extra attempts (0 for `.lock` writes, §D4).
  /// Returns: `({bool is412, String? error})` — null error on success.
  /// Side effects: Performs network I/O; may create/replace the remote file.
  /// Notes: feature-matrix §A13.  30s timeout.  HTTP 412 returns the standard
  /// message `'conditional WebDAV PUT failed (HTTP 412)'`.  Conditional headers
  /// are used for `.lock` writes only; data JSON writes go through the sync
  /// engine without preconditions.  `Content-Type` is always
  /// `application/octet-stream` (matching the apps).
  Future<({bool is412, String? error})> upload(
    String name,
    String content, {
    String? ifMatchEtag,
    bool ifNoneMatchAll = false,
    int retries = 2,
  }) async {
    try {
      final url = Uri.parse(remoteFileUrl(name));
      final client = _clientForCall();
      final response = await withRetry(
        () => client
            .put(
              url,
              headers: {
                ...authHeaders(),
                'Content-Type': 'application/octet-stream',
                'If-Match': ?ifMatchEtag,
                if (ifNoneMatchAll) 'If-None-Match': '*',
              },
              body: utf8.encode(content),
            )
            .timeout(const Duration(seconds: 30)),
        shouldRetry: (r) => r.statusCode >= 500,
        retries: retries,
      );
      if (response.statusCode == 412) {
        return (is412: true, error: 'conditional WebDAV PUT failed (HTTP 412)');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (is412: false, error: null);
      }
      return (is412: false, error: 'HTTP ${response.statusCode}');
    } catch (e) {
      return (is412: false, error: '$e');
    }
  }

  /// Purpose: Upload binary bytes to a remote WebDAV path.
  /// Inputs: [name] remote file name; [bytes] binary body.
  /// Returns: None.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A14 (unified on `Future<void>`; return value was
  /// unused in all apps).  120s timeout.  Retries on 5xx.  Throws
  /// `Exception('HTTP $code')` on non-2xx.  Used for image uploads.
  Future<void> uploadBytes(String name, Uint8List bytes) async {
    final url = Uri.parse(remoteFileUrl(name));
    final client = _clientForCall();
    final response = await withRetry(
      () => client
          .put(
            url,
            headers: {
              ...authHeaders(),
              'Content-Type': 'application/octet-stream',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 120)),
      shouldRetry: (r) => r.statusCode >= 500,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
  }

  /// Purpose: Download binary bytes from a remote WebDAV path.
  /// Inputs: [name] remote file name.
  /// Returns: `Future<Uint8List>` — the file bytes.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A16 (unified on `Future<Uint8List>`; null was never
  /// returned).  120s timeout.  Retries on 5xx.  Throws
  /// `Exception('HTTP $code')` on non-200.  Used for image downloads.
  Future<Uint8List> downloadBytes(String name) async {
    final url = Uri.parse(remoteFileUrl(name));
    final client = _clientForCall();
    final response = await withRetry(
      () => client
          .get(url, headers: authHeaders())
          .timeout(const Duration(seconds: 120)),
      shouldRetry: (r) => r.statusCode >= 500,
    );
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('HTTP ${response.statusCode}');
  }

  /// Purpose: Delete a remote file.
  /// Inputs: [name] remote file name; [etag] optional `If-Match` ETag.
  /// Returns: None.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A17.  10s timeout.  Swallows all errors (stale
  /// locks expire after TTL).  The redundant 404 early-return (MyAnime) is
  /// dropped (§A17 — already swallowed).
  Future<void> delete(String name, {String? etag}) async {
    try {
      final client = _clientForCall();
      await client
          .delete(
            Uri.parse(remoteFileUrl(name)),
            headers: {...authHeaders(), 'If-Match': ?etag},
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Purpose: List file names in a remote sub-directory via PROPFIND Depth:1.
  /// Inputs: [name] sub-directory name.
  /// Returns: `Future<Set<String>?>` — file names, or `null` when the listing
  /// failed (unknown remote state).
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §C-P1-§C-P4/§A18.  Uses [propfindTimeout].  A `null`
  /// result means the remote state is unknown; callers must **not** treat it as
  /// an empty directory (would re-upload every referenced image on transient
  /// failure).  Adopts MyDevice's `<(?:\w+:)?href>` regex (§C-P1, most robust)
  /// and `p.basename` for name extraction (§C-P2).
  Future<Set<String>?> listSubDir(String name) async {
    try {
      final url = Uri.parse(remoteFileUrl('$name/'));
      final client = _clientForCall();
      final streamed = await withRetry(() {
        final request = http.Request('PROPFIND', url);
        request.headers.addAll(authHeaders());
        request.headers['Depth'] = '1';
        request.headers['Content-Type'] = 'application/xml';
        request.body =
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';
        return client.send(request).timeout(propfindTimeout);
      }, shouldRetry: (r) => r.statusCode >= 500);
      if (streamed.statusCode != 207) return null;

      final body = await streamed.stream.bytesToString();
      final hrefPattern = RegExp(
        r'<(?:\w+:)?href>([^<]+)</(?:\w+:)?href>',
        caseSensitive: false,
      );
      final names = <String>{};
      for (final m in hrefPattern.allMatches(body)) {
        final href = Uri.decodeFull(m.group(1)!);
        if (href.endsWith('/')) continue; // skip directories (§C-P2)
        final fileName = p.basename(href);
        if (fileName.isNotEmpty) names.add(fileName);
      }
      return names;
    } catch (_) {
      return null;
    }
  }

  // ── Remote upload-lock primitives ──
  //
  // These methods perform **remote-only** operations on the `.lock` file.
  // Local lock-file persistence and client-ID management belong to the sync
  // engine (P2.6) which composes these primitives with `StorageAdapter`.

  /// Purpose: Read and parse the remote `.lock` file.
  /// Inputs: None.
  /// Returns: `({WebDAVUploadLock? lock, String? etag, String? error})`.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §B.  Missing or malformed locks return
  /// `(lock: null, etag: <strong-or-null>, error: null)` (treated as
  /// replaceable stale locks).  Transport errors return the error string.
  /// Only strong ETags are returned for `If-Match` preconditions.
  Future<({WebDAVUploadLock? lock, String? etag, String? error})>
  readRemoteUploadLock() async {
    final remote = await download(lockFileName);
    if (remote.status == RemoteFileStatus.error) {
      return (lock: null, etag: null, error: remote.error);
    }
    if (remote.status == RemoteFileStatus.notFound || remote.content == null) {
      return (lock: null, etag: null, error: null);
    }
    try {
      final json = jsonDecode(remote.content!) as Map<String, dynamic>;
      return (
        lock: WebDAVUploadLock.fromJson(json),
        etag: strongEtag(remote.etag),
        error: null,
      );
    } catch (_) {
      return (lock: null, etag: strongEtag(remote.etag), error: null);
    }
  }

  /// Purpose: Write the remote `.lock` file with optional preconditions.
  /// Inputs: [lock] the lock value; [ifMatchEtag] optional `If-Match`;
  /// [ifNoneMatchAll] create-only flag.
  /// Returns: Upload result `({is412, error})`.
  /// Side effects: Performs network I/O; may create/replace `.lock`.
  /// Notes: feature-matrix §B10.  Uses `retries: 0` so a retried create-only
  /// PUT cannot misreport lock contention (§D4).
  Future<({bool is412, String? error})> writeRemoteUploadLock(
    WebDAVUploadLock lock, {
    String? ifMatchEtag,
    bool ifNoneMatchAll = false,
  }) {
    return upload(
      lockFileName,
      jsonEncode(lock.toJson()),
      ifMatchEtag: ifMatchEtag,
      ifNoneMatchAll: ifNoneMatchAll,
      retries: 0,
    );
  }

  /// Purpose: Delete the remote `.lock` file.
  /// Inputs: [etag] optional `If-Match` ETag.
  /// Returns: None.
  /// Side effects: Performs network I/O.
  /// Notes: feature-matrix §A17/§B.  Swallows all errors (stale locks expire
  /// after TTL).  Delegates to [delete].
  Future<void> deleteRemoteUploadLock({String? etag}) {
    return delete(lockFileName, etag: etag);
  }

  // ── Heartbeat ──

  /// Purpose: Run a transfer while heartbeat-refreshing the held upload lock.
  /// Inputs: [refreshLock] closure that re-writes the remote/local lock;
  /// [operation] the in-flight transfer.
  /// Returns: The operation's result.
  /// Side effects: Periodically calls [refreshLock] at [heartbeatInterval]
  /// until [operation] completes.
  /// Notes: feature-matrix §B6.  Without a heartbeat, a single PUT slower than
  /// the lock TTL would let another client treat the lock as expired and upload
  /// concurrently.  Heartbeat failures are swallowed: they must never abort a
  /// transfer that is already in flight.  The [refreshLock] closure is provided
  /// by the sync engine (P2.6) which combines remote lock refresh with local
  /// lock-file persistence.
  Future<T> withLockHeartbeat<T>({
    required Future<void> Function() refreshLock,
    required Future<T> Function() operation,
  }) async {
    var refreshing = false;
    final timer = Timer.periodic(heartbeatInterval, (_) async {
      if (refreshing) return;
      refreshing = true;
      try {
        await refreshLock();
      } catch (_) {
        // Best-effort: the pre-PUT refresh already validated ownership.
      } finally {
        refreshing = false;
      }
    });
    try {
      return await operation();
    } finally {
      timer.cancel();
    }
  }
}
