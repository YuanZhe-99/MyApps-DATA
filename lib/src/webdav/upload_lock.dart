/// Purpose: WebDAV upload-lock value type and session handle.
/// Inputs: None (library declaration only).
/// Returns: N/A.
/// Side effects: None.
/// Notes: The upload-lock subsystem is byte-identical across all three apps
/// (feature-matrix §B1-B11).  It moves here verbatim with TTL/heartbeat
/// injectable for tests but defaults fixed (I3).  Local lock-file persistence
/// and client-ID management stay in the sync engine (P2.6) which has
/// `StorageAdapter` access; this file holds only the value type and session
/// handle.
library;

import 'dart:convert' show jsonEncode;

/// Default lock TTL in seconds (feature-matrix §B5, I3).
const int defaultLockTtlSeconds = 60;

/// A WebDAV upload lock stored in the remote `.lock` file.
///
/// Schema (feature-matrix §B4, byte-identical across all three apps):
/// `{clientId, token, startedAt, updatedAt, ttlSeconds}` with UTC ISO8601
/// timestamps.
class WebDAVUploadLock {
  /// Stable local client identifier (UUID v4, persisted in `.sync_base/client_id.txt`).
  final String clientId;

  /// Per-upload token (UUID v4, regenerated each session unless resuming).
  final String token;

  /// When this lock was first acquired (UTC).
  final DateTime startedAt;

  /// Last heartbeat refresh time (UTC).
  final DateTime updatedAt;

  /// Lock time-to-live in seconds.
  final int ttlSeconds;

  /// Purpose: Create a WebDAV upload lock value.
  /// Inputs: [clientId], [token], [startedAt], [updatedAt], [ttlSeconds].
  /// Returns: A new [WebDAVUploadLock] instance.
  /// Side effects: None.
  /// Notes: Times should be in UTC; [startedAt] and [updatedAt] are normalised
  /// to UTC by the factory and `refreshed`.
  const WebDAVUploadLock({
    required this.clientId,
    required this.token,
    required this.startedAt,
    required this.updatedAt,
    required this.ttlSeconds,
  });

  /// Purpose: Parse a WebDAV upload lock from JSON.
  /// Inputs: [json] decoded map from the remote `.lock` file.
  /// Returns: A parsed [WebDAVUploadLock].
  /// Side effects: None.
  /// Notes: Throws when required fields are missing or malformed.  `ttlSeconds`
  /// defaults to [defaultLockTtlSeconds] when absent (feature-matrix §B5).
  factory WebDAVUploadLock.fromJson(Map<String, dynamic> json) {
    return WebDAVUploadLock(
      clientId: json['clientId'] as String,
      token: json['token'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      ttlSeconds: json['ttlSeconds'] as int? ?? defaultLockTtlSeconds,
    );
  }

  /// Purpose: Serialize this lock to the remote `.lock` JSON format.
  /// Inputs: None.
  /// Returns: JSON-compatible map.
  /// Side effects: None.
  /// Notes: Timestamps are emitted as UTC ISO8601 strings.
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'token': token,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'ttlSeconds': ttlSeconds,
  };

  /// Purpose: Return whether this lock is expired at [now].
  /// Inputs: [now] current time (will be normalised to UTC).
  /// Returns: `true` when `now - updatedAt >= ttlSeconds`.
  /// Side effects: None.
  /// Notes: feature-matrix §B11.  Expired locks are treated as failed uploads
  /// and may be replaced by another client.
  bool isExpired(DateTime now) =>
      now.toUtc().difference(updatedAt.toUtc()).inSeconds >= ttlSeconds;

  /// Purpose: Return whether this lock belongs to the given session.
  /// Inputs: [clientId], [token].
  /// Returns: `true` when both fields match.
  /// Side effects: None.
  /// Notes: Used before refreshing or deleting remote locks.
  bool matches(String clientId, String token) =>
      this.clientId == clientId && this.token == token;

  /// Purpose: Create a refreshed copy of this lock with an updated [updatedAt].
  /// Inputs: [updatedAt] new heartbeat timestamp.
  /// Returns: A new [WebDAVUploadLock].
  /// Side effects: None.
  /// Notes: Keeps the original `clientId`, `token`, `startedAt`, and
  /// `ttlSeconds`.
  WebDAVUploadLock refreshed(DateTime updatedAt) => WebDAVUploadLock(
    clientId: clientId,
    token: token,
    startedAt: startedAt,
    updatedAt: updatedAt.toUtc(),
    ttlSeconds: ttlSeconds,
  );

  /// Purpose: Encode this lock as a JSON string.
  /// Inputs: None.
  /// Returns: JSON string suitable for PUT to the remote `.lock` file.
  /// Side effects: None.
  /// Notes: Convenience for [WebDavClient.writeRemoteUploadLock].
  @override
  String toString() => jsonEncode(toJson());
}

/// Handle for an upload session holding a remote `.lock`.
///
/// In the apps this was the private `_UploadSession`; it is public here so the
/// sync engine (P2.6) can pass it between lock-management calls on
/// [WebDavClient].
class UploadSession {
  /// The client ID that owns this session.
  final String clientId;

  /// The upload token matching the remote `.lock`.
  final String token;

  /// Purpose: Create an upload session handle.
  /// Inputs: [clientId], [token].
  /// Returns: A new [UploadSession] instance.
  /// Side effects: None.
  /// Notes: Value type; equality is identity (matching the apps' usage where
  /// the session is compared by reference).
  const UploadSession({required this.clientId, required this.token});
}
