/// Purpose: Exchange one application's secrets file with its WebDAV server,
/// only when the endpoint passes the secure-endpoint policy.
/// Inputs: A [SecretStore], the WebDAV config just synced with, the device's
/// trusted hosts, and the exchange mode.
/// Returns: A [SecretExchangeOutcome] describing what happened.
/// Side effects: At most two GETs and two PUTs of the secrets file; may rewrite
/// the local secrets file.
/// Notes: Runs after the sync engine returns, outside its `.lock`, against the
/// same server and remote directory. The engine lock protects three-way merges
/// against a base snapshot; the secrets file has neither, and a conditional PUT
/// turns a concurrent write into a re-read and re-merge rather than a lost
/// update.
library;

import 'dart:convert';

import '../webdav/endpoint_security.dart';
import '../webdav/webdav_client.dart';
import '../webdav/webdav_config.dart';
import 'secret_store.dart';
import 'secrets_document.dart';

/// Which direction an exchange runs in.
enum SecretExchangeMode {
  /// Download, merge per key, write locally and upload conditionally.
  sync,

  /// Replace the remote copy with the local one; no merge, local untouched.
  forceUpload,

  /// Replace the local copy with the remote one; no merge, no upload.
  forceDownload,
}

/// What became of the secrets during an exchange.
enum SecretExchangeStatus {
  /// The secrets were exchanged, or already agreed.
  synced,

  /// The endpoint failed the secure-endpoint policy; no request was made.
  skippedInsecure,

  /// Neither side had an entry, so nothing was sent or written.
  nothingToDo,

  /// The exchange was attempted and failed.
  failed,
}

/// The outcome of one exchange.
class SecretExchangeOutcome {
  /// What happened.
  final SecretExchangeStatus status;

  /// The endpoint verdict the exchange was gated on.
  final EndpointVerdict verdict;

  /// Whether the local file changed.
  final bool downloaded;

  /// Whether the remote file was written.
  final bool uploaded;

  /// How many usable keys in the store's namespaces the local file holds
  /// afterwards; tombstones are not counted.
  final int keyCount;

  /// What went wrong, when [status] is [SecretExchangeStatus.failed].
  final String? error;

  /// Purpose: Record an outcome.
  /// Inputs: All fields.
  /// Returns: An immutable value.
  /// Side effects: None.
  /// Notes: None.
  const SecretExchangeOutcome({
    required this.status,
    required this.verdict,
    this.downloaded = false,
    this.uploaded = false,
    this.keyCount = 0,
    this.error,
  });

  /// Purpose: Name why the endpoint was accepted or refused.
  /// Inputs: None.
  /// Returns: The verdict's [EndpointReason].
  /// Side effects: None.
  /// Notes: Present for every status, so the UI can always explain.
  EndpointReason get reason => verdict.reason;
}

/// Exchanges one application's secrets file with its WebDAV server.
class SecretExchange {
  /// Purpose: Create an exchange over [store].
  /// Inputs: [store] the local secrets file; optional [clientFactory] building
  /// the WebDAV client (tests inject one over a fake server).
  /// Returns: A new [SecretExchange].
  /// Side effects: None.
  /// Notes: The remote file name is [SecretStore.fileName].
  SecretExchange({
    required this.store,
    WebDavClient Function(WebDAVConfig config)? clientFactory,
  }) : _clientFactory = clientFactory ?? WebDavClient.new;

  /// The local secrets file.
  final SecretStore store;

  /// Builds the WebDAV client for one exchange.
  final WebDavClient Function(WebDAVConfig config) _clientFactory;

  /// Purpose: Exchange secrets with the server, if the endpoint allows it.
  /// Inputs: [config] the WebDAV config just synced with; [trustedHosts] this
  /// device accepts for plain HTTP; [mode].
  /// Returns: A [SecretExchangeOutcome]; never throws.
  /// Side effects: Network I/O and possibly a local write, as described per
  /// mode below.
  /// Notes: A refused endpoint makes no request in either direction. The
  /// local read, merge and write run under [SecretStore.withLock], and no
  /// network call is made while it is held. A local I/O error fails the
  /// exchange before anything is uploaded.
  Future<SecretExchangeOutcome> exchange(
    WebDAVConfig config, {
    List<String> trustedHosts = const [],
    SecretExchangeMode mode = SecretExchangeMode.sync,
  }) async {
    final verdict = evaluateEndpointUrl(
      config.serverUrl,
      trustedHosts: trustedHosts,
    );
    if (!verdict.allowed) {
      return SecretExchangeOutcome(
        status: SecretExchangeStatus.skippedInsecure,
        verdict: verdict,
      );
    }
    try {
      final client = _clientFactory(config);
      return switch (mode) {
        SecretExchangeMode.sync => await _sync(client, verdict),
        SecretExchangeMode.forceUpload => await _forceUpload(client, verdict),
        SecretExchangeMode.forceDownload => await _forceDownload(
          client,
          verdict,
        ),
      };
    } catch (error) {
      return SecretExchangeOutcome(
        status: SecretExchangeStatus.failed,
        verdict: verdict,
        error: '$error',
      );
    }
  }

  /// Purpose: Run the merging exchange.
  /// Inputs: [client], [verdict].
  /// Returns: The outcome.
  /// Side effects: GET, locked merge and local write, conditional PUT; on
  /// HTTP 412 one more GET, locked re-merge and conditional PUT.
  /// Notes: Internal helper. A remote file that does not parse is treated as
  /// absent. A failed re-read after 412 fails without uploading.
  Future<SecretExchangeOutcome> _sync(
    WebDavClient client,
    EndpointVerdict verdict,
  ) async {
    final remote = await client.download(store.fileName);
    if (remote.status == RemoteFileStatus.error) {
      return _failed(verdict, remote.error);
    }
    final theirs = _parse(remote) ?? SecretsDocument();

    final step = await store.withLock(() async {
      final local = await store.loadForWrite();
      if (local.keys.isEmpty && theirs.keys.isEmpty) {
        return (merged: local, changed: false, nothing: true);
      }
      final merged = mergeSecretsDocuments(local, theirs);
      final changed = !_same(local, merged);
      if (changed) await store.saveQuiet(merged);
      return (merged: merged, changed: changed, nothing: false);
    });
    if (step.nothing) {
      return SecretExchangeOutcome(
        status: SecretExchangeStatus.nothingToDo,
        verdict: verdict,
      );
    }
    final merged = step.merged;
    if (_same(theirs, merged)) {
      return _synced(verdict, merged, downloaded: step.changed);
    }

    var result = await client.upload(
      store.fileName,
      encodeSecretsDocument(merged),
      ifMatchEtag: WebDavClient.strongEtag(remote.etag),
      ifNoneMatchAll: remote.status == RemoteFileStatus.notFound,
    );
    if (!result.is412) {
      if (result.error != null) {
        return _failed(
          verdict,
          result.error,
          downloaded: step.changed,
          document: merged,
        );
      }
      return _synced(verdict, merged, downloaded: step.changed, uploaded: true);
    }

    final again = await client.download(store.fileName);
    if (again.status == RemoteFileStatus.error) {
      return _failed(
        verdict,
        again.error,
        downloaded: step.changed,
        document: merged,
      );
    }
    final theirsAgain = _parse(again) ?? SecretsDocument();
    final rebased = await store.withLock(() async {
      final current = await store.loadForWrite();
      final next = mergeSecretsDocuments(
        mergeSecretsDocuments(current, merged),
        theirsAgain,
      );
      if (!_same(current, next)) await store.saveQuiet(next);
      return next;
    });
    result = await client.upload(
      store.fileName,
      encodeSecretsDocument(rebased),
      ifMatchEtag: WebDavClient.strongEtag(again.etag),
      ifNoneMatchAll: again.status == RemoteFileStatus.notFound,
    );
    if (result.error != null) {
      return _failed(
        verdict,
        result.error,
        downloaded: true,
        document: rebased,
      );
    }
    return _synced(verdict, rebased, downloaded: true, uploaded: true);
  }

  /// Purpose: Replace the remote copy with the local one.
  /// Inputs: [client], [verdict].
  /// Returns: The outcome.
  /// Side effects: One unconditional PUT when the local file has entries.
  /// Notes: Internal helper. The local file is read under the lock (an
  /// unparseable one is set aside) and never written. An empty local file
  /// uploads nothing, so a fresh device cannot wipe the server.
  Future<SecretExchangeOutcome> _forceUpload(
    WebDavClient client,
    EndpointVerdict verdict,
  ) async {
    final local = await store.withLock(store.loadForWrite);
    if (local.keys.isEmpty) {
      return SecretExchangeOutcome(
        status: SecretExchangeStatus.nothingToDo,
        verdict: verdict,
      );
    }
    final result = await client.upload(
      store.fileName,
      encodeSecretsDocument(local),
    );
    if (result.error != null) {
      return _failed(verdict, result.error, document: local);
    }
    return _synced(verdict, local, uploaded: true);
  }

  /// Purpose: Replace the local copy with the remote one.
  /// Inputs: [client], [verdict].
  /// Returns: The outcome.
  /// Side effects: One GET; a locked local write when the remote parses and
  /// differs.
  /// Notes: Internal helper. A missing remote file keeps the local one; a
  /// remote file that does not parse fails without writing.
  Future<SecretExchangeOutcome> _forceDownload(
    WebDavClient client,
    EndpointVerdict verdict,
  ) async {
    final remote = await client.download(store.fileName);
    if (remote.status == RemoteFileStatus.error) {
      return _failed(verdict, remote.error);
    }
    if (remote.status == RemoteFileStatus.notFound) {
      final local = await store.load();
      return SecretExchangeOutcome(
        status: local.keys.isEmpty
            ? SecretExchangeStatus.nothingToDo
            : SecretExchangeStatus.synced,
        verdict: verdict,
        keyCount: _ownedKeyCount(local),
      );
    }
    final theirs = _parse(remote);
    if (theirs == null) {
      return _failed(verdict, '${store.fileName}: remote content is not valid');
    }
    final changed = await store.withLock(() async {
      final local = await store.loadForWrite();
      if (_same(local, theirs)) return false;
      await store.saveQuiet(theirs);
      return true;
    });
    return _synced(verdict, theirs, downloaded: changed);
  }

  /// Purpose: Build a success outcome.
  /// Inputs: [verdict], the local [document] afterwards, direction flags.
  /// Returns: A [SecretExchangeStatus.synced] outcome.
  /// Side effects: None.
  /// Notes: Internal helper.
  SecretExchangeOutcome _synced(
    EndpointVerdict verdict,
    SecretsDocument document, {
    bool downloaded = false,
    bool uploaded = false,
  }) => SecretExchangeOutcome(
    status: SecretExchangeStatus.synced,
    verdict: verdict,
    downloaded: downloaded,
    uploaded: uploaded,
    keyCount: _ownedKeyCount(document),
  );

  /// Purpose: Count the usable keys in this app's namespaces.
  /// Inputs: [document].
  /// Returns: The count.
  /// Side effects: None.
  /// Notes: Internal helper. Tombstones and foreign ids are not counted.
  int _ownedKeyCount(SecretsDocument document) =>
      document.configuredIds.where(store.ownsId).length;

  /// Purpose: Build a failure outcome.
  /// Inputs: [verdict], the [error], whether the local file changed, and the
  /// local [document] afterwards when known.
  /// Returns: A [SecretExchangeStatus.failed] outcome.
  /// Side effects: None.
  /// Notes: Internal helper.
  SecretExchangeOutcome _failed(
    EndpointVerdict verdict,
    String? error, {
    bool downloaded = false,
    SecretsDocument? document,
  }) => SecretExchangeOutcome(
    status: SecretExchangeStatus.failed,
    verdict: verdict,
    downloaded: downloaded,
    keyCount: document == null ? 0 : _ownedKeyCount(document),
    error: error ?? 'unknown error',
  );

  /// Purpose: Parse a downloaded secrets file.
  /// Inputs: The [remote] response.
  /// Returns: The document; empty for a missing file; null when the content
  /// is not a JSON object.
  /// Side effects: None.
  /// Notes: Internal helper.
  static SecretsDocument? _parse(RemoteFile remote) {
    if (remote.status != RemoteFileStatus.found) return SecretsDocument();
    try {
      final decoded = jsonDecode(remote.content ?? '');
      if (decoded is! Map<String, dynamic>) return null;
      return SecretsDocument.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  /// Purpose: Compare two documents by encoded content.
  /// Inputs: [a], [b].
  /// Returns: True when both encode to the same bytes.
  /// Side effects: None.
  /// Notes: Internal helper.
  static bool _same(SecretsDocument a, SecretsDocument b) =>
      encodeSecretsDocument(a) == encodeSecretsDocument(b);
}
