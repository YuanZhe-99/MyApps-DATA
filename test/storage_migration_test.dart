import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

/// Purpose: Create a file with [content], making parent directories as needed.
/// Inputs: [dir] root, [relative] path under it, [content].
/// Returns: The written file.
/// Side effects: Writes to disk.
/// Notes: Test helper only.
Future<File> _write(Directory dir, String relative, String content) async {
  final file = File(p.join(dir.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

/// Purpose: Read a file under [dir], or null when absent.
/// Inputs: [dir] root, [relative] path.
/// Returns: File content or null.
/// Side effects: Reads from disk.
/// Notes: Test helper only.
Future<String?> _read(Directory dir, String relative) async {
  final file = File(p.join(dir.path, relative));
  return await file.exists() ? file.readAsString() : null;
}

void main() {
  late Directory root;
  late Directory from;
  late Directory to;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('myapps-data-migration-');
    from = Directory(p.join(root.path, 'old'))..createSync(recursive: true);
    to = Directory(p.join(root.path, 'new'))..createSync(recursive: true);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('moves the whole managed set, not just data files', () async {
    // Exactly the set the old per-app implementations stranded.
    await _write(from, 'anime_data.json', '{"animes":[]}');
    await _write(from, 'webdav_config.json', '{"serverUrl":"s"}');
    await _write(from, 'images/cover.png', 'IMG');
    await _write(from, '.sync_base/anime_data.json', '{"base":true}');
    await _write(from, '.sync_base/client_id.txt', 'client-1');
    await _write(from, 'backups/backup_20260101_000000.json', '{"_b":2}');
    await _write(from, 'backups/blobs/abc123.png', 'BLOB');

    final failed = await migrateStorageContents(from: from, to: to);

    expect(failed, isEmpty);
    expect(await _read(to, 'anime_data.json'), '{"animes":[]}');
    expect(await _read(to, 'webdav_config.json'), '{"serverUrl":"s"}');
    expect(await _read(to, 'images/cover.png'), 'IMG');
    expect(await _read(to, '.sync_base/anime_data.json'), '{"base":true}');
    expect(await _read(to, '.sync_base/client_id.txt'), 'client-1');
    expect(await _read(to, 'backups/backup_20260101_000000.json'), '{"_b":2}');
    expect(await _read(to, 'backups/blobs/abc123.png'), 'BLOB');

    // Sources are gone, so nothing is left stranded at the old location.
    expect(await File(p.join(from.path, 'anime_data.json')).exists(), isFalse);
    expect(await Directory(p.join(from.path, 'images')).exists(), isFalse);
    expect(await Directory(p.join(from.path, '.sync_base')).exists(), isFalse);
  });

  test(
    'migrates files nobody enumerated — the property that prevents this bug '
    'from coming back',
    () async {
      // A data file added in some future release, plus a nested directory no
      // migration list ever mentioned. Both must move with zero code changes.
      await _write(from, 'a_brand_new_module.json', '{"new":true}');
      await _write(from, 'future_dir/nested/deep.bin', 'DEEP');

      final failed = await migrateStorageContents(from: from, to: to);

      expect(failed, isEmpty);
      expect(await _read(to, 'a_brand_new_module.json'), '{"new":true}');
      expect(await _read(to, 'future_dir/nested/deep.bin'), 'DEEP');
    },
  );

  test('never moves storage_config.json — it holds the path itself', () async {
    await _write(from, 'storage_config.json', '{"storagePath":"/old"}');
    await _write(from, 'anime_data.json', '{}');

    await migrateStorageContents(from: from, to: to);

    expect(await _read(from, 'storage_config.json'), '{"storagePath":"/old"}');
    expect(await _read(to, 'storage_config.json'), isNull);
    expect(await _read(to, 'anime_data.json'), '{}');
  });

  test('existing destination data wins and the source copy survives', () async {
    await _write(from, 'anime_data.json', 'OLD');
    await _write(to, 'anime_data.json', 'DESTINATION');
    await _write(from, 'images/shared.png', 'OLD-IMG');
    await _write(to, 'images/shared.png', 'DEST-IMG');
    await _write(from, 'images/only-old.png', 'ONLY-OLD');

    final failed = await migrateStorageContents(from: from, to: to);

    expect(failed, isEmpty);
    // Destination content is untouched…
    expect(await _read(to, 'anime_data.json'), 'DESTINATION');
    expect(await _read(to, 'images/shared.png'), 'DEST-IMG');
    // …and the skipped source is NOT deleted, so no data is discarded on a
    // guess about which copy is newer.
    expect(await _read(from, 'anime_data.json'), 'OLD');
    expect(await _read(from, 'images/shared.png'), 'OLD-IMG');
    // Non-conflicting files still move.
    expect(await _read(to, 'images/only-old.png'), 'ONLY-OLD');
  });

  test('merges into a partially populated destination', () async {
    await _write(from, 'backups/blobs/a.png', 'A');
    await _write(to, 'backups/blobs/b.png', 'B');

    final failed = await migrateStorageContents(from: from, to: to);

    expect(failed, isEmpty);
    expect(await _read(to, 'backups/blobs/a.png'), 'A');
    expect(await _read(to, 'backups/blobs/b.png'), 'B');
  });

  test('creates the destination when it does not exist yet', () async {
    final fresh = Directory(p.join(root.path, 'fresh'));
    await _write(from, 'anime_data.json', '{}');

    final failed = await migrateStorageContents(from: from, to: fresh);

    expect(failed, isEmpty);
    expect(await _read(fresh, 'anime_data.json'), '{}');
  });

  test('same source and destination is a no-op', () async {
    await _write(from, 'anime_data.json', 'KEEP');

    final failed = await migrateStorageContents(from: from, to: from);

    expect(failed, isEmpty);
    expect(await _read(from, 'anime_data.json'), 'KEEP');
  });

  test('missing source directory is a no-op, not an error', () async {
    final absent = Directory(p.join(root.path, 'absent'));

    final failed = await migrateStorageContents(from: absent, to: to);

    expect(failed, isEmpty);
  });
}
