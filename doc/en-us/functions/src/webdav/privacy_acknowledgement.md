# lib/src/webdav/privacy_acknowledgement.dart

Per-device acknowledgement of the WebDAV privacy notice. Applications own the notice version (an
integer raised whenever the data scope or terms change materially) and decide when to pause or
resume sync from the status this file computes.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `webDavPrivacyAcknowledgementKey` | constant | A | Default `storage_config.json` key, `webdavPrivacyAcknowledgement`. |
| `WebDavPrivacyAcknowledgement` | class | A | Confirmed notice version, UTC time and preserved unknown fields. |
| `WebDavPrivacyAcknowledgement(...)` | constructor | A | Creates a record, normalising the time to UTC. |
| `WebDavPrivacyAcknowledgement.tryParse` | static method | A | Parses a stored value; malformed values are absent. |
| `WebDavPrivacyAcknowledgement.toJson` | method | A | Serializes the record with unknown fields. |
| `WebDavPrivacyStatus` | enum | A | `acknowledged`, `firstEnable`, `syncPaused`. |
| `needsAcknowledgement` | function | A | True when nothing is stored or the stored version is older. |
| `webDavPrivacyStatus` | function | A | Classifies the device for sync gating and UI. |
| `WebDavPrivacyAcknowledgementStore` | class | A | Device-local persistence through injected callbacks. |
| `WebDavPrivacyAcknowledgementStore(...)` | constructor | A | Binds read/write callbacks. |
| `WebDavPrivacyAcknowledgementStore.storageConfig` | factory | A | Stores the record under a `storage_config.json` key via `StorageAdapter`. |
| `load` | method | A | Loads the stored record. |
| `acknowledge` | method | A | Records confirmation of a version. |
| `clear` | method | A | Removes the record. |

Fourteen declarations.

## Stored record

```json
{
  "noticeVersion": 1,
  "acknowledgedAt": "2026-10-06T12:00:00.000Z"
}
```

## Behavior

- `needsAcknowledgement(stored, currentVersion)` is true for `null` or a version below
  `currentVersion`. A newer stored version, for example after a downgrade, counts as confirmed.
- `webDavPrivacyStatus` returns `syncPaused` when sync is already configured but unconfirmed, which
  covers existing users after an upgrade. Applications keep the configuration and pending data,
  show `MyAppsWebDavSyncPausedBanner`, and run no sync until the user confirms.
- `firstEnable` means the notice must be shown before the first network request; declining stores
  nothing.
- The record is never a data module: it is not synced, backed up or exported, so every new device
  shows the notice.
- The `storageConfig` factory performs read-modify-write and keeps every other key; unknown fields
  of an existing record survive `acknowledge`.
- Nothing here changes the WebDAV wire format, remote layout, `.lock` semantics or conflict handling.
