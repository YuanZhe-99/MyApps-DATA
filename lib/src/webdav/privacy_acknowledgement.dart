/// Purpose: Model the per-device acknowledgement of the WebDAV privacy notice.
/// Inputs: A stored acknowledgement record and the app's current notice version.
/// Returns: Pure acknowledgement decisions and an injected-persistence store.
/// Side effects: Only [WebDavPrivacyAcknowledgementStore] performs I/O, through
/// application-supplied callbacks.
/// Notes: The record is device-local. It must never be a data module, so sync,
/// backup and ZIP export never carry it and a new device always shows the
/// notice. Nothing here changes sync behavior, the wire format, the remote
/// layout, `.lock` semantics or conflict handling; applications decide when to
/// pause and resume sync from [webDavPrivacyStatus].
library;

import '../storage/storage_adapter.dart';

/// Default `storage_config.json` key used by
/// [WebDavPrivacyAcknowledgementStore.storageConfig].
const String webDavPrivacyAcknowledgementKey = 'webdavPrivacyAcknowledgement';

/// A device's record that the user confirmed one version of the notice.
class WebDavPrivacyAcknowledgement {
  /// The notice version the user confirmed.
  final int noticeVersion;

  /// When the user confirmed it, in UTC.
  final DateTime acknowledgedAt;

  /// Fields this package does not model, preserved on write.
  final Map<String, dynamic> extra;

  /// Purpose: Create an acknowledgement record.
  /// Inputs: [noticeVersion], [acknowledgedAt] and optional unknown [extra]
  /// fields.
  /// Returns: An immutable record.
  /// Side effects: None.
  /// Notes: [acknowledgedAt] is normalised to UTC.
  WebDavPrivacyAcknowledgement({
    required this.noticeVersion,
    required DateTime acknowledgedAt,
    Map<String, dynamic> extra = const {},
  }) : acknowledgedAt = acknowledgedAt.toUtc(),
       extra = Map.unmodifiable(extra);

  /// Purpose: Parse a stored acknowledgement.
  /// Inputs: A JSON-compatible [json] value.
  /// Returns: The record, or null when [json] is missing or malformed.
  /// Side effects: None.
  /// Notes: A malformed record is treated as absent so the notice is shown
  /// again rather than silently skipped. Unknown fields go to [extra].
  static WebDavPrivacyAcknowledgement? tryParse(Object? json) {
    if (json is! Map) return null;
    final version = json['noticeVersion'];
    final at = json['acknowledgedAt'];
    if (version is! int || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return WebDavPrivacyAcknowledgement(
      noticeVersion: version,
      acknowledgedAt: parsed,
      extra: {
        for (final entry in json.entries)
          if (entry.key is String &&
              entry.key != 'noticeVersion' &&
              entry.key != 'acknowledgedAt')
            entry.key as String: entry.value,
      },
    );
  }

  /// Purpose: Serialize the record for storage.
  /// Inputs: None.
  /// Returns: A JSON-compatible map including preserved unknown fields.
  /// Side effects: None.
  /// Notes: The timestamp is written as a UTC ISO-8601 string.
  Map<String, dynamic> toJson() => {
    ...extra,
    'noticeVersion': noticeVersion,
    'acknowledgedAt': acknowledgedAt.toIso8601String(),
  };
}

/// Where a device stands with respect to the privacy notice.
enum WebDavPrivacyStatus {
  /// The current notice version is confirmed; sync may run.
  acknowledged,

  /// Sync is not configured yet; show the notice before enabling it.
  firstEnable,

  /// Sync is configured but the current notice is unconfirmed; keep the
  /// configuration and pending data, visibly pause sync until confirmed.
  syncPaused,
}

/// Purpose: Decide whether the user must confirm the notice again.
/// Inputs: The [stored] record (null when none) and the app's [currentVersion].
/// Returns: True when nothing is stored or the stored version is older.
/// Side effects: None.
/// Notes: A record for a newer version than [currentVersion] (for example after
/// a downgrade) counts as confirmed.
bool needsAcknowledgement(
  WebDavPrivacyAcknowledgement? stored,
  int currentVersion,
) => stored == null || stored.noticeVersion < currentVersion;

/// Purpose: Classify the device's notice state for sync gating and UI.
/// Inputs: Whether WebDAV sync is already configured/enabled
/// ([syncConfigured]), the [stored] record and [currentVersion].
/// Returns: A [WebDavPrivacyStatus].
/// Side effects: None.
/// Notes: Existing users with sync configured but no record get
/// [WebDavPrivacyStatus.syncPaused]; applications must keep pending data and
/// show that sync is paused rather than dropping anything.
WebDavPrivacyStatus webDavPrivacyStatus({
  required bool syncConfigured,
  required WebDavPrivacyAcknowledgement? stored,
  required int currentVersion,
}) {
  if (!needsAcknowledgement(stored, currentVersion)) {
    return WebDavPrivacyStatus.acknowledged;
  }
  return syncConfigured
      ? WebDavPrivacyStatus.syncPaused
      : WebDavPrivacyStatus.firstEnable;
}

/// Device-local persistence for the acknowledgement through injected callbacks.
class WebDavPrivacyAcknowledgementStore {
  final Future<Object?> Function() _read;
  final Future<void> Function(Map<String, dynamic>? json) _write;

  /// Purpose: Bind the store to application persistence.
  /// Inputs: [read] returns the stored JSON value (or null); [write] persists
  /// a JSON map, or removes the record when given null.
  /// Returns: A store.
  /// Side effects: None until a method is called.
  /// Notes: The backing location must be device-local and never a data module.
  WebDavPrivacyAcknowledgementStore({
    required Future<Object?> Function() read,
    required Future<void> Function(Map<String, dynamic>? json) write,
  }) : _read = read,
       _write = write;

  /// Purpose: Store the acknowledgement under a key of `storage_config.json`.
  /// Inputs: The app's [storage] adapter and an optional [key].
  /// Returns: A store using read-modify-write through the adapter.
  /// Side effects: None until a method is called.
  /// Notes: Other configuration keys are preserved. `storage_config.json` is
  /// not a data module, so the record is not synced, backed up or exported.
  factory WebDavPrivacyAcknowledgementStore.storageConfig(
    StorageAdapter storage, {
    String key = webDavPrivacyAcknowledgementKey,
  }) => WebDavPrivacyAcknowledgementStore(
    read: () async => (await storage.readConfig())[key],
    write: (json) async {
      final config = await storage.readConfig();
      if (json == null) {
        config.remove(key);
      } else {
        config[key] = json;
      }
      await storage.writeConfig(config);
    },
  );

  /// Purpose: Load the stored acknowledgement.
  /// Inputs: None.
  /// Returns: The record, or null when absent or malformed.
  /// Side effects: Calls the injected read callback.
  /// Notes: Read errors propagate to the caller.
  Future<WebDavPrivacyAcknowledgement?> load() async =>
      WebDavPrivacyAcknowledgement.tryParse(await _read());

  /// Purpose: Record that the user confirmed [noticeVersion].
  /// Inputs: [noticeVersion] and an optional [now] for tests.
  /// Returns: The stored record.
  /// Side effects: Calls the injected write callback.
  /// Notes: Unknown fields of an existing record are preserved.
  Future<WebDavPrivacyAcknowledgement> acknowledge(
    int noticeVersion, {
    DateTime? now,
  }) async {
    final previous = await load();
    final record = WebDavPrivacyAcknowledgement(
      noticeVersion: noticeVersion,
      acknowledgedAt: now ?? DateTime.now().toUtc(),
      extra: previous?.extra ?? const {},
    );
    await _write(record.toJson());
    return record;
  }

  /// Purpose: Remove the stored acknowledgement.
  /// Inputs: None.
  /// Returns: A future completing after removal.
  /// Side effects: Calls the injected write callback with null.
  /// Notes: Use when the user wants to review the notice again.
  Future<void> clear() => _write(null);
}
