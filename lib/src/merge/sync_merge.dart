/// Purpose: Generic three-way record merge engine extracted from MyAnime,
/// MyDay, and MyDevice.
/// Inputs: Local/remote/base record lists plus id/timestamp/display callbacks.
/// Returns: A merged list and any unresolved conflicts.
/// Side effects: None (pure transform).
/// Notes: P2.3 unifies the three near-identical `mergeRecords<T>` variants.
/// MyAnime and MyDay are byte-identical; MyDevice is a strict superset that adds
/// an optional `mergeUnknownFields` callback for model-level `extraJson`
/// preservation. This implementation adopts the superset signature so all three
/// apps' call sites work unchanged (the callback is optional/nullable).
/// Deletion semantics, identical-content suppression, and `autoResolve` defaults
/// are pinned by P0.1 (matrix §E); app-specific merge wrappers and
/// `mergeAssignments` stay app-side.
library;

/// A single record-level conflict: same ID, both sides changed since base.
class RecordConflict<T> {
  /// ID of the conflicted record (value of the `getId` callback).
  final String id;

  /// Local version of the record.
  final T localRecord;

  /// Remote version of the record.
  final T remoteRecord;

  /// Human-readable name for UI conflict dialogs.
  final String displayName;

  /// Purpose: Create a record conflict instance.
  /// Inputs: [id], [localRecord], [remoteRecord], [displayName].
  /// Returns: A new [RecordConflict] instance.
  /// Side effects: None.
  /// Notes: None.
  const RecordConflict({
    required this.id,
    required this.localRecord,
    required this.remoteRecord,
    required this.displayName,
  });
}

/// Result of merging a list of records.
class RecordMergeResult<T> {
  /// Merged records (winning side for each ID, excluding deletions).
  final List<T> merged;

  /// Conflicts that require manual resolution (only when `autoResolve` is
  /// false and both sides changed differently).
  final List<RecordConflict<T>> conflicts;

  /// Purpose: Create a record merge result instance.
  /// Inputs: [merged], [conflicts].
  /// Returns: A new [RecordMergeResult] instance.
  /// Side effects: None.
  /// Notes: None.
  const RecordMergeResult({required this.merged, this.conflicts = const []});
}

/// Purpose: Three-way merge a list of records by ID using `modifiedAt`.
/// Inputs: [local], [remote], [base], [getId], [getModifiedAt],
/// [getDisplayName], [autoResolve], optional [serialize], optional
/// [mergeUnknownFields].
/// Returns: A [RecordMergeResult] with the merged list and any conflicts.
/// Side effects: None.
/// Notes: Behavior (pinned by P0.1 matrix §E):
/// - Only local changed -> use local.
/// - Only remote changed -> use remote.
/// - Both changed, identical serialized content -> no conflict (use local).
/// - Both changed, different content -> conflict (or LWW when [autoResolve]).
/// - Neither changed -> use local.
/// - New record on one side only -> include it.
/// - Record deleted on one side, unchanged on other -> exclude (deletion
///   propagates).
/// - Record deleted on one side, modified on other -> keep the modification.
/// - Deleted both sides -> exclude.
/// - No base (first sync / both added same ID) -> LWW by `modifiedAt` (ties go
///   to remote).
/// [autoResolve] defaults to `false` (PLAN invariant I4); every production call
/// site passes `false`. [serialize], when provided, enables identical-content
/// conflict suppression. [mergeUnknownFields] (MyDevice pattern) lets apps with
/// model-level `extraJson` preserve unknown fields through the merge.
RecordMergeResult<T> mergeRecords<T>({
  required List<T> local,
  required List<T> remote,
  required List<T>? base,
  required String Function(T) getId,
  required DateTime Function(T) getModifiedAt,
  required String Function(T) getDisplayName,
  T Function(T primary, T secondary, T? base)? mergeUnknownFields,
  bool autoResolve = false,
  String Function(T)? serialize,
}) {
  final localMap = {for (final r in local) getId(r): r};
  final remoteMap = {for (final r in remote) getId(r): r};
  final baseMap = base != null
      ? {for (final r in base) getId(r): r}
      : <String, T>{};

  final allIds = {...localMap.keys, ...remoteMap.keys, ...baseMap.keys};
  final merged = <T>[];
  final conflicts = <RecordConflict<T>>[];
  T preserveUnknown(T primary, T secondary, T? base) =>
      mergeUnknownFields?.call(primary, secondary, base) ?? primary;

  for (final id in allIds) {
    final l = localMap[id];
    final r = remoteMap[id];
    final b = baseMap[id];

    if (l != null && r != null) {
      // Both sides have the record.
      if (b != null) {
        // Three-way: check who changed from base.
        final localChanged = getModifiedAt(l).isAfter(getModifiedAt(b));
        final remoteChanged = getModifiedAt(r).isAfter(getModifiedAt(b));

        if (localChanged && remoteChanged) {
          if (serialize != null && serialize(l) == serialize(r)) {
            // Identical content on both sides is not a real conflict.
            merged.add(preserveUnknown(l, r, b));
          } else if (autoResolve) {
            final primary = getModifiedAt(l).isAfter(getModifiedAt(r)) ? l : r;
            final secondary = identical(primary, l) ? r : l;
            merged.add(preserveUnknown(primary, secondary, b));
          } else {
            conflicts.add(
              RecordConflict(
                id: id,
                localRecord: preserveUnknown(l, r, b),
                remoteRecord: preserveUnknown(r, l, b),
                displayName: getDisplayName(l),
              ),
            );
          }
        } else if (localChanged) {
          merged.add(preserveUnknown(l, r, b));
        } else if (remoteChanged) {
          merged.add(preserveUnknown(r, l, b));
        } else {
          merged.add(preserveUnknown(l, r, b)); // neither changed
        }
      } else {
        // No base - first sync or both added same ID.
        final primary = getModifiedAt(l).isAfter(getModifiedAt(r)) ? l : r;
        final secondary = identical(primary, l) ? r : l;
        merged.add(preserveUnknown(primary, secondary, null));
      }
    } else if (l != null && r == null) {
      if (b != null) {
        // Was in base, missing from remote -> deleted remotely.
        final localChanged = getModifiedAt(l).isAfter(getModifiedAt(b));
        if (localChanged) {
          merged.add(l); // modified locally after remote deleted -> keep
        }
        // else: not modified locally, remote deleted -> exclude
      } else {
        merged.add(l); // new locally -> include
      }
    } else if (l == null && r != null) {
      if (b != null) {
        // Was in base, missing from local -> deleted locally.
        final remoteChanged = getModifiedAt(r).isAfter(getModifiedAt(b));
        if (remoteChanged) {
          merged.add(r); // modified remotely after local deleted -> keep
        }
        // else: not modified remotely, local deleted -> exclude
      } else {
        merged.add(r); // new remotely -> include
      }
    }
    // else: both null, was in base -> deleted both sides -> exclude
  }

  return RecordMergeResult(merged: merged, conflicts: conflicts);
}
