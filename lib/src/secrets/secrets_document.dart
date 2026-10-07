/// Purpose: Model the local API-key secrets file and the rule for merging two
/// copies of it.
/// Inputs: Parsed secrets-file JSON.
/// Returns: [SecretEntry] and [SecretsDocument] value types, the per-key
/// merge, and the canonical encoder.
/// Side effects: None.
/// Notes: The shape is the one MyTranscribe already writes to
/// `transcribe_secrets.json` — `{"version": 1, "keys": {"ID": {"apiKey":
/// ..., "updatedAt": ...}}}` — so an existing file reads and re-encodes
/// byte-identically. A secrets file is never a data module: sync, backup and
/// ZIP engines only touch registry file names, which is what keeps keys out of
/// every bundle and export structurally.
library;

import 'dart:convert';

/// The format version written into a secrets file.
///
/// Passed through so a future shape can be recognised; nothing branches on it.
const int secretsDocumentVersion = 1;

/// One key and when it was last set or cleared.
class SecretEntry {
  /// The key itself, or null for a tombstone.
  ///
  /// Null is a deletion that must propagate, not an absence: without it the
  /// other device's copy would come back on the next exchange.
  final String? apiKey;

  /// When the key was last set or cleared, in UTC.
  final DateTime updatedAt;

  /// Entry fields written by a build this one does not model.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create an entry.
  /// Inputs: [apiKey] (null for a tombstone), [updatedAt], optional unknown
  /// [extraJson] fields.
  /// Returns: An immutable value.
  /// Side effects: None.
  /// Notes: [updatedAt] is normalised to UTC.
  SecretEntry({
    required this.apiKey,
    required DateTime updatedAt,
    Map<String, dynamic> extraJson = const {},
  }) : updatedAt = updatedAt.toUtc(),
       extraJson = Map.unmodifiable(extraJson);

  /// Purpose: Report whether a usable key is present.
  /// Inputs: None.
  /// Returns: False for a tombstone or a blank key.
  /// Side effects: None.
  /// Notes: None.
  bool get hasKey => apiKey != null && apiKey!.isNotEmpty;

  /// Purpose: Parse one entry.
  /// Inputs: [json].
  /// Returns: A [SecretEntry].
  /// Side effects: None.
  /// Notes: A non-string or empty `apiKey` reads as a tombstone. An unreadable
  /// timestamp falls back to the epoch, so a damaged entry loses to any real
  /// one rather than winning every merge. Unknown fields go to [extraJson].
  factory SecretEntry.fromJson(Map<String, dynamic> json) {
    final key = json['apiKey'];
    return SecretEntry(
      apiKey: key is String && key.isNotEmpty ? key : null,
      updatedAt:
          DateTime.tryParse('${json['updatedAt']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      extraJson: {
        for (final e in json.entries)
          if (e.key != 'apiKey' && e.key != 'updatedAt') e.key: e.value,
      },
    );
  }

  /// Purpose: Serialize one entry.
  /// Inputs: None.
  /// Returns: A JSON-compatible map.
  /// Side effects: None.
  /// Notes: A tombstone is written as an explicit `"apiKey": null`. Unknown
  /// fields are written first, then `apiKey` and `updatedAt`, so an entry
  /// without unknown fields matches MyTranscribe's bytes.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'apiKey': apiKey,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Every key one secrets file holds.
class SecretsDocument {
  /// Entries by record id, for example `provider:openai`.
  final Map<String, SecretEntry> keys;

  /// Top-level fields written by a build this one does not model.
  final Map<String, dynamic> extraJson;

  /// Purpose: Create a document.
  /// Inputs: [keys], [extraJson].
  /// Returns: An immutable value.
  /// Side effects: None.
  /// Notes: None.
  SecretsDocument({
    Map<String, SecretEntry> keys = const {},
    Map<String, dynamic> extraJson = const {},
  }) : keys = Map.unmodifiable(keys),
       extraJson = Map.unmodifiable(extraJson);

  /// Purpose: Parse a document.
  /// Inputs: [json].
  /// Returns: A [SecretsDocument].
  /// Side effects: None.
  /// Notes: A `keys` value of the wrong type, and entries that are not
  /// objects, read as absent rather than throwing. `version` is not kept; it
  /// is rewritten as [secretsDocumentVersion].
  factory SecretsDocument.fromJson(Map<String, dynamic> json) {
    final raw = json['keys'];
    return SecretsDocument(
      keys: raw is! Map
          ? const {}
          : {
              for (final entry in raw.entries)
                if (entry.key is String && entry.value is Map<String, dynamic>)
                  entry.key as String: SecretEntry.fromJson(
                    entry.value as Map<String, dynamic>,
                  ),
            },
      extraJson: {
        for (final e in json.entries)
          if (e.key != 'keys' && e.key != 'version') e.key: e.value,
      },
    );
  }

  /// Purpose: Serialize the document.
  /// Inputs: None.
  /// Returns: A JSON-compatible map.
  /// Side effects: None.
  /// Notes: Ids are sorted so equal content always encodes to equal bytes,
  /// which lets the exchange skip writes and uploads that change nothing.
  Map<String, dynamic> toJson() => {
    ...extraJson,
    'version': secretsDocumentVersion,
    'keys': {
      for (final id in keys.keys.toList()..sort()) id: keys[id]!.toJson(),
    },
  };

  /// Purpose: Read one id's usable key.
  /// Inputs: [id].
  /// Returns: The key, or null when absent or a tombstone.
  /// Side effects: None.
  /// Notes: None.
  String? keyFor(String id) {
    final entry = keys[id];
    return entry != null && entry.hasKey ? entry.apiKey : null;
  }

  /// Purpose: Set or clear one id's key.
  /// Inputs: [id], [apiKey] (null or blank clears it), optional [now].
  /// Returns: A new [SecretsDocument].
  /// Side effects: None.
  /// Notes: The key is trimmed. Clearing writes a tombstone so the deletion
  /// survives the next exchange. Unknown fields of an existing entry are kept.
  SecretsDocument withKey(String id, String? apiKey, {DateTime? now}) {
    final trimmed = apiKey?.trim();
    return SecretsDocument(
      keys: {
        ...keys,
        id: SecretEntry(
          apiKey: trimmed == null || trimmed.isEmpty ? null : trimmed,
          updatedAt: (now ?? DateTime.now()).toUtc(),
          extraJson: keys[id]?.extraJson ?? const {},
        ),
      },
      extraJson: extraJson,
    );
  }

  /// Purpose: List the ids that currently hold a usable key.
  /// Inputs: None.
  /// Returns: Their ids; never a key value.
  /// Side effects: None.
  /// Notes: None.
  Set<String> get configuredIds => {
    for (final entry in keys.entries)
      if (entry.value.hasKey) entry.key,
  };
}

/// Purpose: Merge two copies of a secrets file, per key, by recency.
/// Inputs: [local], [remote].
/// Returns: The merged document.
/// Side effects: None.
/// Notes: Last writer wins per key by `updatedAt`, tombstones included, so a
/// cleared key stays cleared everywhere. A tie goes to [remote], so every
/// device converges. No base snapshot is involved: each key is one independent
/// value. Top-level unknown fields are unioned with [local] winning.
SecretsDocument mergeSecretsDocuments(
  SecretsDocument local,
  SecretsDocument remote,
) {
  final merged = <String, SecretEntry>{};
  for (final id in {...local.keys.keys, ...remote.keys.keys}) {
    final mine = local.keys[id];
    final theirs = remote.keys[id];
    if (mine == null) {
      merged[id] = theirs!;
    } else if (theirs == null) {
      merged[id] = mine;
    } else {
      merged[id] = mine.updatedAt.isAfter(theirs.updatedAt) ? mine : theirs;
    }
  }
  return SecretsDocument(
    keys: merged,
    extraJson: {...remote.extraJson, ...local.extraJson},
  );
}

/// Purpose: Encode a secrets document the way it is stored and uploaded.
/// Inputs: [document].
/// Returns: Pretty-printed JSON (two-space indent).
/// Side effects: None.
/// Notes: One encoder for local writes and uploads, so unchanged content
/// produces identical bytes.
String encodeSecretsDocument(SecretsDocument document) =>
    const JsonEncoder.withIndent('  ').convert(document.toJson());
