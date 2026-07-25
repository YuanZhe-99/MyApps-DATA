/// Purpose: Generic ZIP data transfer engine extracted from the three apps'
/// `import_export_service.dart` implementations (feature-matrix §M).
/// Inputs: A [StorageAdapter], an ordered [ModuleRegistry], the per-app
/// archive name prefix, and behavior knobs preserving per-app strictness.
/// Returns: ZIP export paths and boolean import outcomes.
/// Side effects: Performs local file-system I/O: export writes one timestamped
/// archive into a caller-chosen directory; import overwrites allowlisted app
/// data files and images inside the app directory.
/// Notes: Export bundles exactly the registry's data files plus flat
/// `images/<basename>` entries - never `storage_config.json`,
/// `webdav_config.json`, `.sync_base/`, or `backups/` (M4/M5). Import is
/// standardized on MyDay's strict semantics: `p.url.normalize` + traversal
/// rejection (M6). Per-app leniency survives as knobs (M7/M8/M9). Markdown
/// export is a non-goal and stays app-side (M14).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../modules/data_module.dart';
import '../storage/atomic_io.dart';
import '../storage/storage_adapter.dart';

/// Purpose: Supply the current time to the ZIP transfer engine.
/// Inputs: None.
/// Returns: The current local [DateTime].
/// Side effects: None.
/// Notes: Injectable for tests; production uses [DateTime.now]. Archive name
/// timestamps are local-time values in all three apps.
typedef ZipClock = DateTime Function();

/// Purpose: Run app-defined work after a successful ZIP import.
/// Inputs: None.
/// Returns: A future completing after the hook.
/// Side effects: App-defined.
/// Notes: Feature-matrix §M10: no current app disables auto-sync on import
/// (a flagged latent gap); this optional hook lets an app close it without
/// engine changes. It is not invoked on failed imports.
typedef ZipAfterImportHook = FutureOr<void> Function();

/// Generic ZIP export/import engine parameterized by storage and registry.
class ZipTransfer {
  /// Purpose: Create a ZIP transfer engine.
  /// Inputs: [storage], [modules], [archiveNamePrefix], and optional knobs
  /// [rejectUnknownEntries] (M7), [strictUtf8] (M8), [validateBeforeWrite]
  /// (M9), [atomicWrites] (M9), [clock], and [onAfterImport] (M10).
  /// Returns: A new [ZipTransfer].
  /// Side effects: None until methods are invoked.
  /// Notes: [archiveNamePrefix] preserves each app's existing archive naming:
  /// `myanime_export_`, `myday_backup_`, `mydevice_export_` (M1). All knobs
  /// default to MyDay's strict behavior.
  ZipTransfer({
    required this.storage,
    required this.modules,
    required this.archiveNamePrefix,
    this.rejectUnknownEntries = true,
    this.strictUtf8 = true,
    this.validateBeforeWrite = true,
    this.atomicWrites = true,
    this.onAfterImport,
    ZipClock? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _imagesDirName = 'images';

  /// App-supplied active storage root.
  final StorageAdapter storage;

  /// Ordered app module registry; iteration order is the export entry order
  /// and identifies which archive entries count as data files (M3).
  final ModuleRegistry modules;

  /// Per-app archive file-name prefix (M1); the stamp and `.zip` suffix are
  /// fixed (M2).
  final String archiveNamePrefix;

  /// Whether an unknown or malformed archive entry fails the whole import
  /// (true = MyDay) or is skipped (false = MyAnime/MyDevice) (M7).
  final bool rejectUnknownEntries;

  /// Whether data entries must decode as strict UTF-8 (true = MyDay) or are
  /// written as raw bytes (false = MyAnime/MyDevice) (M8).
  final bool strictUtf8;

  /// Whether every data entry is validated through [DataModule.validate]
  /// before any file is written (true = MyDay, M9). When false, no validator
  /// runs (MyAnime/MyDevice).
  final bool validateBeforeWrite;

  /// Whether writes use tmp-then-rename atomic replacement (true = MyDay) or
  /// plain `writeAsBytes` (false = MyAnime/MyDevice) (M9).
  final bool atomicWrites;

  /// Optional hook invoked once after a successful import (M10).
  final ZipAfterImportHook? onAfterImport;

  final ZipClock _clock;

  /// Purpose: Format a local timestamp as `yyyyMMdd_HHmmss`.
  /// Inputs: [value].
  /// Returns: The archive name timestamp.
  /// Side effects: None.
  /// Notes: Matches the apps' `DateFormat('yyyyMMdd_HHmmss')` output without
  /// taking an `intl` dependency (M2).
  static String _formatStamp(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}${two(value.month)}'
        '${two(value.day)}_${two(value.hour)}${two(value.minute)}'
        '${two(value.second)}';
  }

  /// Purpose: Return whether [childPath] stays inside [rootPath].
  /// Inputs: [rootPath], [childPath].
  /// Returns: True when the normalized child equals or lives under the root.
  /// Side effects: None.
  /// Notes: MyDay's containment check; defense-in-depth behind the allowlist
  /// so a crafted archive can never write outside the app directory (M6).
  static bool _isInside(String rootPath, String childPath) {
    final root = p.normalize(rootPath);
    final child = p.normalize(childPath);
    return child == root || child.startsWith('$root${p.separator}');
  }

  /// Purpose: Export all app data as a ZIP file.
  /// Inputs: [destDir] destination directory path.
  /// Returns: The exported file path, or null on failure.
  /// Side effects: Reads app data files/images and writes a ZIP file with
  /// `flush: true` (M11).
  /// Notes: Entries are the registry's existing data files in registry order
  /// followed by flat `images/<basename>` entries (M3/M5); encoding uses
  /// `package:archive` defaults with no encryption (M13).
  Future<String?> exportZip(String destDir) async {
    try {
      final appDir = await storage.getAppDir();
      final archive = Archive();

      for (final module in modules.modules) {
        final file = File(p.join(appDir.path, module.fileName));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(module.fileName, bytes.length, bytes));
        }
      }

      final imagesDir = Directory(p.join(appDir.path, _imagesDirName));
      if (await imagesDir.exists()) {
        await for (final entity in imagesDir.list()) {
          if (entity is File) {
            final bytes = await entity.readAsBytes();
            final name = 'images/${p.basename(entity.path)}';
            archive.addFile(ArchiveFile(name, bytes.length, bytes));
          }
        }
      }

      final zipData = ZipEncoder().encode(archive);
      final stamp = _formatStamp(_clock());
      final outFile = File(p.join(destDir, '$archiveNamePrefix$stamp.zip'));
      await outFile.writeAsBytes(zipData, flush: true);
      return outFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Import app data from a previously exported ZIP file.
  /// Inputs: [filePath].
  /// Returns: True when the archive passed all checks and was imported.
  /// Side effects: Overwrites allowlisted app data files and images inside
  /// the app directory, then runs [onAfterImport] when set.
  /// Notes: Two-phase: every entry is classified (and, when
  /// [validateBeforeWrite], validated) before any file is written, so a
  /// rejected archive never leaves partial writes. Traversal entries always
  /// fail the import (M6); unknown/malformed entries follow
  /// [rejectUnknownEntries] (M7); data payloads follow [strictUtf8] and
  /// [validateBeforeWrite] (M8/M9). Import never triggers re-sync or backup
  /// (M10).
  Future<bool> importZip(String filePath) async {
    try {
      final zipFile = File(filePath);
      if (!await zipFile.exists()) return false;

      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      final appDir = await storage.getAppDir();
      final appRoot = p.normalize(appDir.absolute.path);
      final dataWrites = <String, List<int>>{};
      final imageWrites = <String, List<int>>{};

      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final normalized = p.url.normalize(entry.name).replaceAll('\\', '/');
        if (normalized.startsWith('../') || normalized.contains('/../')) {
          return false;
        }

        final module = modules.byFileName[normalized];
        if (module != null) {
          final rawBytes = List<int>.from(entry.content as List<int>);
          if (strictUtf8 || validateBeforeWrite) {
            final content = utf8.decode(rawBytes, allowMalformed: !strictUtf8);
            if (validateBeforeWrite) {
              module.validate(content);
            }
          }
          dataWrites[normalized] = rawBytes;
          continue;
        }

        if (normalized.startsWith('images/')) {
          final basename = p.basename(normalized);
          if (basename.isEmpty || normalized != 'images/$basename') {
            if (rejectUnknownEntries) return false;
            continue;
          }
          imageWrites[basename] = List<int>.from(entry.content as List<int>);
          continue;
        }

        if (rejectUnknownEntries) return false;
      }

      for (final item in dataWrites.entries) {
        final target = File(p.join(appDir.path, item.key));
        if (!_isInside(appRoot, target.absolute.path)) return false;
        await _writeBytes(target, item.value);
      }

      for (final item in imageWrites.entries) {
        final target = File(p.join(appDir.path, _imagesDirName, item.key));
        if (!_isInside(appRoot, target.absolute.path)) return false;
        await _writeBytes(target, item.value);
      }

      await onAfterImport?.call();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Purpose: Write one extracted entry honoring [atomicWrites].
  /// Inputs: [target], [bytes].
  /// Returns: A future completing after the write.
  /// Side effects: Creates parent directories and replaces [target].
  /// Notes: Atomic mode uses the P2.4 tmp-then-rename helper; plain mode
  /// matches MyAnime/MyDevice's direct `writeAsBytes` (M9). Bytes are always
  /// the original entry payload, byte-identical to MyDay's decode-then-write
  /// for valid UTF-8.
  Future<void> _writeBytes(File target, List<int> bytes) async {
    if (atomicWrites) {
      await atomicWriteBytes(target, bytes);
      return;
    }
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await target.writeAsBytes(bytes);
  }
}
