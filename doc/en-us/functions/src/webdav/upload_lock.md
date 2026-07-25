# lib/src/webdav/upload_lock.dart

WebDAV upload-lock value type and session handle. The upload-lock subsystem is byte-identical
across all three apps (feature-matrix §B1-B11). This file holds only the value type and session
handle; local lock-file persistence and client-ID management stay in the sync engine (P2.6).

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| [`defaultLockTtlSeconds`](#defaultlockttlseconds-constant) | constant | A | Default lock TTL (60s, feature-matrix §B5). |
| [`WebDAVUploadLock`](#webdavuploadlock-class) | class | A | Remote `.lock` value type with JSON round-trip, expiry check, session match, and heartbeat refresh. |
| [`UploadSession`](#uploadsession-class) | class | A | Handle for an upload session holding a remote `.lock`. |

## Documentation

### `defaultLockTtlSeconds` constant <a id="defaultlockttlseconds-constant"></a>

- **Source:** `lib/src/webdav/upload_lock.dart`.
- **Value:** `60` (feature-matrix §B5, I3).
- **Purpose:** Default TTL in seconds for `WebDAVUploadLock.fromJson` when `ttlSeconds` is absent.

### `WebDAVUploadLock` class <a id="webdavuploadlock-class"></a>

- **Source:** `lib/src/webdav/upload_lock.dart`.
- **Purpose:** Represents a WebDAV upload lock stored in the remote `.lock` file. Schema:
  `{clientId, token, startedAt, updatedAt, ttlSeconds}` with UTC ISO8601 timestamps
  (feature-matrix §B4).
- **Fields:**
  - `clientId` (`String`) - stable local client identifier (UUID v4).
  - `token` (`String`) - per-upload token (UUID v4, regenerated each session unless resuming).
  - `startedAt` (`DateTime`) - when this lock was first acquired (UTC).
  - `updatedAt` (`DateTime`) - last heartbeat refresh time (UTC).
  - `ttlSeconds` (`int`) - lock time-to-live in seconds.
- **Constructors:**
  - `WebDAVUploadLock({required clientId, required token, required startedAt, required updatedAt, required ttlSeconds})`.
  - `WebDAVUploadLock.fromJson(Map<String, dynamic>)` - parses from the remote `.lock` JSON;
    `ttlSeconds` defaults to `defaultLockTtlSeconds` (60) when absent.
- **Methods:**
  - `toJson()` - serializes to the `.lock` JSON format with UTC ISO8601 timestamps.
  - `isExpired(DateTime now)` - `true` when `now - updatedAt >= ttlSeconds` (§B11).
  - `matches(String clientId, String token)` - `true` when both fields match (§B7).
  - `refreshed(DateTime updatedAt)` - returns a copy with the new `updatedAt` (keeps `clientId`,
    `token`, `startedAt`, `ttlSeconds`).
  - `toString()` - encodes as a JSON string (convenience for `WebDavClient.writeRemoteUploadLock`).

### `UploadSession` class <a id="uploadsession-class"></a>

- **Source:** `lib/src/webdav/upload_lock.dart`.
- **Purpose:** Handle for an upload session holding a remote `.lock`. In the apps this was the
  private `_UploadSession`; it is public here so the sync engine (P2.6) can pass it between
  lock-management calls on `WebDavClient`.
- **Fields:** `clientId` (`String`), `token` (`String`).
- **Constructor:** `UploadSession({required clientId, required token})`.
- **Notes:** Value type; equality is identity (matching the apps' usage).
