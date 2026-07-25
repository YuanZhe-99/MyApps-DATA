/// Purpose: Generic, schema-driven and flat-map JSON unknown-field
/// preservation engines extracted from MyDay and MyDevice.
/// Inputs: JSON maps / strings plus optional schemas and base snapshots.
/// Returns: JSON maps / strings with unknown (future) fields preserved across
/// parse -> merge -> write round trips (PLAN invariant I6).
/// Side effects: None (pure transforms); the file-based helper reads a file.
/// Notes: P2.2 reconciles two coexisting preservation styles. (1) MyDay's
/// schema-driven engine describes a data file's shape with
/// [JsonPreservationSchema] and recursively preserves unknown keys; app schemas
/// stay app-side and are passed in. (2) MyDevice's flat helpers operate on
/// model-level `extraJson` maps with a standalone three-way merge. Both are
/// exported so each app can keep its existing preservation strategy unchanged.
library;

import 'dart:convert';
import 'dart:io';

// ─── Schema-driven preservation (from MyDay) ───────────────────────

/// Purpose: Describe how to match and preserve unknown fields inside one list
/// of JSON objects.
/// Inputs: [keyField] and [itemSchema].
/// Returns: A descriptor used by [JsonPreservation].
/// Side effects: None.
/// Notes: Used for `listFields` entries in [JsonPreservationSchema].
class JsonListPreservation {
  /// Name of the JSON key whose value identifies a list item (e.g. `'id'`).
  final String keyField;

  /// Schema describing the known shape of each list item.
  final JsonPreservationSchema itemSchema;

  /// Purpose: Create a json list preservation instance.
  /// Inputs: [keyField], [itemSchema].
  /// Returns: A new [JsonListPreservation] instance.
  /// Side effects: None.
  /// Notes: None.
  const JsonListPreservation({
    required this.keyField,
    required this.itemSchema,
  });
}

/// Purpose: Describe the known shape of one JSON object level so the engine can
/// recurse into known nested fields and preserve unknown ones.
/// Inputs: [knownKeys] and optional nested field descriptors.
/// Returns: A schema consumed by [JsonPreservation].
/// Side effects: None.
/// Notes: Keys absent from [knownKeys] are treated as unknown and preserved
/// verbatim. App field-name schemas do NOT live here - they stay app-side and
/// are passed in at call time.
class JsonPreservationSchema {
  /// Keys this object level models explicitly; everything else is preserved.
  final Set<String> knownKeys;

  /// Known nested object fields (key -> sub-schema) the engine recurses into.
  final Map<String, JsonPreservationSchema> objectFields;

  /// Known list-of-object fields the engine matches by item key and recurses.
  final Map<String, JsonListPreservation> listFields;

  /// Known keyed-map-of-object fields (key -> sub-schema) the engine recurses.
  final Map<String, JsonPreservationSchema> keyedObjectFields;

  /// Purpose: Create a json preservation schema instance.
  /// Inputs: [knownKeys], [objectFields], [listFields], [keyedObjectFields].
  /// Returns: A new [JsonPreservationSchema] instance.
  /// Side effects: None.
  /// Notes: None.
  const JsonPreservationSchema({
    required this.knownKeys,
    this.objectFields = const {},
    this.listFields = const {},
    this.keyedObjectFields = const {},
  });
}

/// Purpose: Schema-driven unknown-field preservation utility (MyDay style).
/// Inputs: A `next` map and one or more source maps plus a schema.
/// Returns: A map with unknown keys from sources merged back onto `next`.
/// Side effects: [encodeForFile] reads an existing file when present.
/// Notes: Use the static utility methods on this type. Recurses into known
/// object/list/keyed-object fields so unknown fields survive at every depth.
class JsonPreservation {
  /// Purpose: Prevent direct instantiation of the JSON preservation utility.
  /// Inputs: None.
  /// Returns: A new [JsonPreservation] instance.
  /// Side effects: None.
  /// Notes: Use the static utility methods on this type instead.
  const JsonPreservation._();

  /// Purpose: Re-inject unknown fields from an existing file into [next] and
  /// return the serialized result.
  /// Inputs: [file] (read if it exists), [next], [schema].
  /// Returns: A JSON string with preserved unknown fields.
  /// Side effects: Reads [file] when present.
  /// Notes: Malformed files are ignored (treated as no source).
  static Future<String> encodeForFile({
    required File file,
    required Map<String, dynamic> next,
    required JsonPreservationSchema schema,
  }) async {
    final sources = <Map<String, dynamic>>[];
    try {
      if (await file.exists()) {
        sources.add(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return jsonEncode(preserve(next: next, sources: sources, schema: schema));
  }

  /// Purpose: Re-inject unknown fields from source JSON strings into [nextJson].
  /// Inputs: [nextJson], [sourceJsons] (null entries skipped), [schema].
  /// Returns: A JSON string with preserved unknown fields.
  /// Side effects: None.
  /// Notes: Malformed source strings are ignored.
  static String preserveJsonString({
    required String nextJson,
    required Iterable<String?> sourceJsons,
    required JsonPreservationSchema schema,
  }) {
    final next = jsonDecode(nextJson) as Map<String, dynamic>;
    final sources = <Map<String, dynamic>>[];
    for (final sourceJson in sourceJsons) {
      if (sourceJson == null) continue;
      try {
        sources.add(jsonDecode(sourceJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    return jsonEncode(preserve(next: next, sources: sources, schema: schema));
  }

  /// Purpose: Re-inject unknown fields from [sources] onto [next].
  /// Inputs: [next], [sources], [schema].
  /// Returns: A new map with unknown fields preserved.
  /// Side effects: None.
  /// Notes: Each source is applied in order via [_preserveOne].
  static Map<String, dynamic> preserve({
    required Map<String, dynamic> next,
    required Iterable<Map<String, dynamic>> sources,
    required JsonPreservationSchema schema,
  }) {
    var result = _copyMap(next);
    for (final source in sources) {
      result = _preserveOne(next: result, source: source, schema: schema);
    }
    return result;
  }

  /// Purpose: Merge unknown fields from one [source] onto [next] recursively.
  /// Inputs: [next], [source], [schema].
  /// Returns: A new map with this source's unknown fields preserved.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static Map<String, dynamic> _preserveOne({
    required Map<String, dynamic> next,
    required Map<String, dynamic> source,
    required JsonPreservationSchema schema,
  }) {
    final result = _copyMap(next);

    for (final entry in schema.objectFields.entries) {
      final nextValue = result[entry.key];
      final sourceValue = source[entry.key];
      if (nextValue is Map && sourceValue is Map) {
        result[entry.key] = _preserveOne(
          next: _stringKeyMap(nextValue),
          source: _stringKeyMap(sourceValue),
          schema: entry.value,
        );
      }
    }

    for (final entry in schema.keyedObjectFields.entries) {
      final nextValue = result[entry.key];
      final sourceValue = source[entry.key];
      if (nextValue is Map && sourceValue is Map) {
        result[entry.key] = _preserveKeyedObjects(
          next: _stringKeyMap(nextValue),
          source: _stringKeyMap(sourceValue),
          schema: entry.value,
        );
      }
    }

    for (final entry in schema.listFields.entries) {
      final nextValue = result[entry.key];
      final sourceValue = source[entry.key];
      if (nextValue is List && sourceValue is List) {
        result[entry.key] = _preserveListItems(
          next: nextValue,
          source: sourceValue,
          listSchema: entry.value,
        );
      }
    }

    for (final entry in source.entries) {
      if (schema.knownKeys.contains(entry.key)) continue;
      result[entry.key] = _copyJsonValue(entry.value);
    }

    return result;
  }

  /// Purpose: Preserve unknown fields across a keyed map of objects.
  /// Inputs: [next], [source], [schema].
  /// Returns: A new keyed map with per-value unknowns preserved.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static Map<String, dynamic> _preserveKeyedObjects({
    required Map<String, dynamic> next,
    required Map<String, dynamic> source,
    required JsonPreservationSchema schema,
  }) {
    final result = _copyMap(next);
    for (final entry in result.entries.toList()) {
      final sourceValue = source[entry.key];
      if (entry.value is Map && sourceValue is Map) {
        result[entry.key] = _preserveOne(
          next: _stringKeyMap(entry.value as Map),
          source: _stringKeyMap(sourceValue),
          schema: schema,
        );
      }
    }
    return result;
  }

  /// Purpose: Preserve unknown fields inside list items matched by key.
  /// Inputs: [next], [source], [listSchema].
  /// Returns: A new list with per-item unknowns preserved.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static List<dynamic> _preserveListItems({
    required List<dynamic> next,
    required List<dynamic> source,
    required JsonListPreservation listSchema,
  }) {
    final sourceByKey = <Object, Map<String, dynamic>>{};
    for (final item in source) {
      if (item is! Map) continue;
      final itemMap = _stringKeyMap(item);
      final key = itemMap[listSchema.keyField];
      if (key != null) sourceByKey[key] = itemMap;
    }

    return next.map((item) {
      if (item is! Map) return _copyJsonValue(item);
      final itemMap = _stringKeyMap(item);
      final key = itemMap[listSchema.keyField];
      final sourceItem = sourceByKey[key];
      if (sourceItem == null) return _copyMap(itemMap);
      return _preserveOne(
        next: itemMap,
        source: sourceItem,
        schema: listSchema.itemSchema,
      );
    }).toList();
  }

  /// Purpose: Deep-copy a JSON map.
  /// Inputs: [map].
  /// Returns: A new `Map<String, dynamic>`.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static Map<String, dynamic> _copyMap(Map<String, dynamic> map) {
    return map.map((key, value) => MapEntry(key, _copyJsonValue(value)));
  }

  /// Purpose: Coerce a `Map` with dynamic keys to `Map<String, dynamic>`.
  /// Inputs: [map].
  /// Returns: A string-keyed map.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static Map<String, dynamic> _stringKeyMap(Map map) {
    return map.map((key, value) => MapEntry(key as String, value));
  }

  /// Purpose: Deep-copy an arbitrary JSON value.
  /// Inputs: [value].
  /// Returns: A deep copy.
  /// Side effects: None.
  /// Notes: Internal helper used within this file only.
  static dynamic _copyJsonValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, child) => MapEntry(key as String, _copyJsonValue(child)),
      );
    }
    if (value is List) {
      return value.map(_copyJsonValue).toList();
    }
    return value;
  }
}

// ─── Flat-map preservation (from MyDevice) ─────────────────────────

/// Purpose: Extract unknown (not-modeled) keys from [json] (MyDevice style).
/// Inputs: [json], [knownKeys].
/// Returns: A map containing only the keys absent from [knownKeys].
/// Side effects: None.
/// Notes: Used by model `fromJson` implementations to capture `extraJson`.
Map<String, dynamic> unknownJsonFields(
  Map<String, dynamic> json,
  Set<String> knownKeys,
) => {
  for (final entry in json.entries)
    if (!knownKeys.contains(entry.key)) entry.key: entry.value,
};

/// Purpose: Three-way merge of unknown-field maps (MyDevice style).
/// Inputs: [primary], [secondary], optional [base].
/// Returns: A merged unknown-field map.
/// Side effects: None.
/// Notes: For each key across all sources: if both sides have it and base has
/// it, a change on only one side wins; if both have it without base, primary
/// wins; if only one side has it, that side wins; if neither has it (base only),
/// the key is removed.
Map<String, dynamic> mergeUnknownJsonFields({
  required Map<String, dynamic> primary,
  required Map<String, dynamic> secondary,
  Map<String, dynamic>? base,
}) {
  final result = <String, dynamic>{...primary};
  final keys = {...primary.keys, ...secondary.keys, ...?base?.keys};

  for (final key in keys) {
    final primaryHas = primary.containsKey(key);
    final secondaryHas = secondary.containsKey(key);
    final baseHas = base?.containsKey(key) ?? false;

    if (primaryHas && secondaryHas) {
      if (baseHas) {
        final baseValue = base![key];
        final primaryChanged = !jsonValueEquals(primary[key], baseValue);
        final secondaryChanged = !jsonValueEquals(secondary[key], baseValue);
        if (!primaryChanged && secondaryChanged) {
          result[key] = secondary[key];
        } else {
          result[key] = primary[key];
        }
      } else {
        result[key] = primary[key];
      }
    } else if (primaryHas) {
      result[key] = primary[key];
    } else if (secondaryHas) {
      result[key] = secondary[key];
    } else {
      result.remove(key);
    }
  }

  return result;
}

/// Purpose: Compare two JSON values for equality by canonical serialization.
/// Inputs: [a], [b].
/// Returns: `true` when the values serialize identically (map keys sorted).
/// Side effects: None.
/// Notes: Used by [mergeUnknownJsonFields] to detect which side changed.
bool jsonValueEquals(Object? a, Object? b) =>
    jsonEncode(_canonicalJson(a)) == jsonEncode(_canonicalJson(b));

/// Purpose: Produce a canonical (key-sorted) form of a JSON value.
/// Inputs: [value].
/// Returns: A canonical `Object?`.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalJson(value[key])};
  }
  if (value is List) {
    return value.map(_canonicalJson).toList();
  }
  return value;
}
