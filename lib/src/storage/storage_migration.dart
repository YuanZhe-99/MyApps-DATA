/// Purpose: Move an app's storage folder contents when the user changes the
/// custom storage path.
/// Inputs: Source and destination directories, plus names to leave behind.
/// Returns: Relative paths that could not be moved (empty on full success).
/// Side effects: Copies files into the destination, then deletes the originals.
/// Notes: Deliberately migrates *everything* rather than an enumerated file
/// list. The bug this replaces was an enumerated list that drifted from what the
/// apps actually stored, silently stranding `.sync_base/`, `backups/`,
/// `images/`, and (in two apps) `webdav_config.json`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Purpose: Move every entry in [from] into [to], skipping named exceptions.
/// Inputs: [from] old storage root, [to] new storage root, [skipNames]
/// top-level entry names to leave in place.
/// Returns: Relative paths that failed to move; empty means complete success.
/// Side effects: Creates directories under [to], copies files, deletes the
/// originals, and removes source directories once they are empty.
/// Notes:
/// - **Copy-then-delete, never move-then-verify.** A failure mid-way leaves a
///   duplicate, never a hole. Losing user data to a half-finished migration
///   would be far worse than leaving a stale copy behind.
/// - **Existing destination entries win.** A file already present at the
///   destination is never overwritten, and its source copy is left alone too,
///   so nothing is destroyed on the strength of a guess about which is newer.
/// - **Per-entry failures are collected, not thrown.** One locked or unreadable
///   file must not abort the rest of the migration and strand the remainder.
/// - [skipNames] exists for `storage_config.json`, which always lives in the
///   platform default directory because it holds the custom path itself.
///   Moving it would make the app forget where its data went.
Future<List<String>> migrateStorageContents({
  required Directory from,
  required Directory to,
  Set<String> skipNames = const {'storage_config.json'},
}) async {
  final failed = <String>[];

  if (p.equals(from.path, to.path)) return failed;
  if (!await from.exists()) return failed;
  if (!await to.exists()) await to.create(recursive: true);

  await for (final entity in from.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (skipNames.contains(name)) continue;

    try {
      if (entity is File) {
        await _moveFile(entity, File(p.join(to.path, name)));
      } else if (entity is Directory) {
        failed.addAll(
          await _moveDirectory(entity, Directory(p.join(to.path, name)), name),
        );
      }
      // Links and other entity types are intentionally left untouched.
    } catch (_) {
      failed.add(name);
    }
  }

  return failed;
}

/// Purpose: Copy one file to its destination and remove the original.
/// Inputs: [source] and [target] file handles.
/// Returns: A future completing after the move or skip.
/// Side effects: May create parent directories, write [target], delete [source].
/// Notes: A pre-existing [target] wins: nothing is written and, importantly,
/// [source] is left in place rather than deleted, so no data is discarded.
Future<void> _moveFile(File source, File target) async {
  if (await target.exists()) return;
  final parent = target.parent;
  if (!await parent.exists()) await parent.create(recursive: true);
  await source.copy(target.path);
  await source.delete();
}

/// Purpose: Recursively move a directory's files, preserving structure.
/// Inputs: [source] and [target] directories, [prefix] for failure reporting.
/// Returns: Relative paths that failed to move.
/// Side effects: Creates directories, copies files, deletes moved originals,
/// and removes source directories that end up empty.
/// Notes: Walks files rather than renaming the directory, so a partially
/// populated destination merges correctly instead of failing outright. This
/// matters for `backups/blobs/`, which may already exist at the destination.
Future<List<String>> _moveDirectory(
  Directory source,
  Directory target,
  String prefix,
) async {
  final failed = <String>[];
  if (!await target.exists()) await target.create(recursive: true);

  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    try {
      await _moveFile(entity, File(p.join(target.path, relative)));
    } catch (_) {
      failed.add(p.join(prefix, relative));
    }
  }

  await _removeEmptyTree(source);
  return failed;
}

/// Purpose: Delete a directory tree, but only the parts that are empty.
/// Inputs: [root] source directory whose files have been moved.
/// Returns: A future completing after the best-effort cleanup.
/// Side effects: Removes empty directories, deepest first.
/// Notes: Deliberately **never** recursive-deletes. Any file still present was
/// skipped because the destination already had that name, and discarding it
/// would destroy the user's data on the strength of a guess. A leftover empty
/// directory is harmless, so every failure here is swallowed.
Future<void> _removeEmptyTree(Directory root) async {
  try {
    final directories = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) directories.add(entity);
    }
    // Deepest first, so a parent becomes empty only after its children go.
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in [...directories, root]) {
      try {
        await directory.delete(); // non-recursive: throws when not empty
      } catch (_) {
        // Still holds a skipped file — leave it and its parents alone.
      }
    }
  } catch (_) {
    // Listing failed; nothing to clean up.
  }
}
