/// Purpose: Generic local backup engine extracted from the three apps'
/// `backup_service.dart` implementations (feature-matrix §J).
/// Inputs: A [StorageAdapter], an ordered [ModuleRegistry], and behavior
/// knobs preserving per-app differences.
/// Returns: Backup creation/listing/restore/deletion plus daily auto-backup.
/// Side effects: Performs local file-system I/O under `<appDir>/backups/`,
/// reads and writes `storage_config.json` backup keys through the adapter,
/// and toggles `webdav_config.json` auto-sync around restores (I5).
/// Notes: Backup format v2 bundles store per-module raw JSON strings plus an
/// `_imageRefs` map pointing at a content-addressed
/// `backups/blobs/<sha256><ext>` store with reference-counted GC. Legacy v1
/// bundles with inline base64 `_images` remain restorable. The engine never
/// writes `createdAt` or `modules` fields (correction C8).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../modules/data_module.dart';
import '../storage/atomic_io.dart';
import '../storage/storage_adapter.dart';
import '../webdav/webdav_config.dart';

/// Purpose: Supply the current time to the backup engine.
/// Inputs: None.
/// Returns: The current local [DateTime].
/// Side effects: None.
/// Notes: Injectable for tests; production uses [DateTime.now]. Backup file
/// names, retention, and the GC grace window are local-time concepts in all
/// three apps, so this clock is deliberately not UTC-normalized.
typedef BackupClock = DateTime Function();

/// Outcome of one backup restore.
class RestoreResult {
  /// Purpose: Create a restore result instance.
  /// Inputs: [ok], [wroteAnything], [missingImages].
  /// Returns: A new [RestoreResult] instance.
  /// Side effects: None.
  /// Notes: [wroteAnything] is false only when the restore failed before
  /// writing any data or image file, so local data is guaranteed untouched.
  /// [missingImages] counts v2 image references whose blob was absent.
  const RestoreResult({
    required this.ok,
    required this.wroteAnything,
    this.missingImages = 0,
  });

  /// Whether the restore completed without an error.
  final bool ok;

  /// Whether any data or image file was written.
  final bool wroteAnything;

  /// Number of v2 `_imageRefs` entries whose blob was missing.
  final int missingImages;
}

/// One listed backup bundle.
class BackupInfo {
  /// Purpose: Create a backup info instance.
  /// Inputs: [file], [date], [sizeBytes], [corrupt].
  /// Returns: A new [BackupInfo] instance.
  /// Side effects: None.
  /// Notes: [sizeBytes] includes referenced blob sizes for probed v2
  /// bundles; [corrupt] marks bundles whose JSON could not be parsed.
  const BackupInfo({
    required this.file,
    required this.date,
    required this.sizeBytes,
    this.corrupt = false,
  });

  /// Bundle file under `backups/`.
  final File file;

  /// Backup date parsed from the filename, or file mtime on parse failure.
  final DateTime date;

  /// Displayed size in bytes, including referenced blob sizes when probed.
  final int sizeBytes;

  /// Whether the bundle JSON could not be parsed during probing.
  final bool corrupt;

  /// Purpose: Format [sizeBytes] for display.
  /// Inputs: None.
  /// Returns: A B/KB/MB string identical to the apps' formatting.
  /// Side effects: None.
  /// Notes: None.
  String get displaySize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Generic local backup engine parameterized by storage and module registry.
class BackupEngine {
  /// Purpose: Create a backup engine.
  /// Inputs: [storage], [modules], [defaultRemotePath], and optional knobs
  /// [syntheticImagesModule] (J3), [blobGcGrace] (J9), [probeMaxBytes] (J12),
  /// and [clock] for tests.
  /// Returns: A new [BackupEngine].
  /// Side effects: None until methods are invoked.
  /// Notes: [defaultRemotePath] is only used to mirror the apps' WebDAV
  /// config load semantics when toggling auto-sync around restores (I5).
  BackupEngine({
    required this.storage,
    required this.modules,
    required this.defaultRemotePath,
    this.syntheticImagesModule = false,
    this.blobGcGrace = const Duration(minutes: 10),
    this.probeMaxBytes = 4 * 1024 * 1024,
    BackupClock? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _backupDirName = 'backups';
  static const _blobSubDirName = 'blobs';
  static const _imagesDirName = 'images';
  static const _webDavConfigFileName = 'webdav_config.json';

  /// Backup bundle format version written by [createBackup] (J4).
  static const formatVersion = 2;

  /// `storage_config.json` key for the auto-backup switch (L1).
  static const autoBackupEnabledKey = 'autoBackupEnabled';

  /// `storage_config.json` key for the retention window in days (L2).
  static const backupRetentionDaysKey = 'backupRetentionDays';

  /// Synthetic restore-selectable module id for images (J3, MyDevice).
  static const imagesModuleId = 'images';

  /// App-supplied active storage root and config persistence.
  final StorageAdapter storage;

  /// Ordered app module registry; iteration order matches the apps' module
  /// maps and therefore bundle key order and restore write order.
  final ModuleRegistry modules;

  /// Per-app fallback WebDAV path applied when a persisted config lacks the
  /// `remotePath` key, mirroring the sync engine's config load.
  final String defaultRemotePath;

  /// Whether restore exposes and gates on a synthetic `images` module
  /// (feature-matrix §J3; true only for MyDevice).
  final bool syntheticImagesModule;

  /// Blobs younger than this are never garbage collected, protecting a
  /// backup that is being written concurrently with a GC pass (§J9).
  final Duration blobGcGrace;

  /// Bundles at or below this size are parsed by [listBackups] to compute
  /// validity and referenced-blob sizes; larger (legacy inline-image)
  /// bundles are listed by file size alone (§J12).
  final int probeMaxBytes;

  final BackupClock _clock;

  /// Whether daily auto-backup is enabled; persisted under
  /// [autoBackupEnabledKey]. Defaults to false (§J11 area).
  bool autoBackupEnabled = false;

  /// Retention window in days; 0 keeps backups forever. Persisted under
  /// [backupRetentionDaysKey].
  int retentionDays = 0;

  DateTime? _lastAutoBackup;
  bool _autoBackupRunning = false;

  /// Purpose: Load backup settings from `storage_config.json`.
  /// Inputs: None.
  /// Returns: A future completing after settings fields are updated.
  /// Side effects: Reads config through the adapter and mutates
  /// [autoBackupEnabled]/[retentionDays].
  /// Notes: Keys and defaults are identical in all three apps (§L1/L2).
  Future<void> loadSettings() async {
    final config = await storage.readConfig();
    autoBackupEnabled = config[autoBackupEnabledKey] as bool? ?? false;
    retentionDays = config[backupRetentionDaysKey] as int? ?? 0;
  }

  /// Purpose: Save backup settings to `storage_config.json`.
  /// Inputs: None.
  /// Returns: A future completing after persistence.
  /// Side effects: Writes config through the adapter, preserving app-owned
  /// keys not modeled by the package.
  /// Notes: The adapter's read-modify-write keeps unrelated keys intact.
  Future<void> saveSettings() async {
    final config = await storage.readConfig();
    config[autoBackupEnabledKey] = autoBackupEnabled;
    config[backupRetentionDaysKey] = retentionDays;
    await storage.writeConfig(config);
  }

  /// Purpose: Resolve (creating when missing) the `backups/` directory.
  /// Inputs: None.
  /// Returns: The backup directory.
  /// Side effects: Creates the directory when missing.
  /// Notes: Internal helper.
  Future<Directory> _getBackupDir() async {
    final appDir = await storage.getAppDir();
    final dir = Directory(p.join(appDir.path, _backupDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Purpose: Resolve (creating when missing) the shared blob directory.
  /// Inputs: None.
  /// Returns: The `backups/blobs/` directory.
  /// Side effects: Creates the directory when missing.
  /// Notes: Internal helper.
  Future<Directory> _getBlobDir() async {
    final backupDir = await _getBackupDir();
    final dir = Directory(p.join(backupDir.path, _blobSubDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Purpose: Format a local timestamp as `yyyyMMdd_HHmmss`.
  /// Inputs: [value].
  /// Returns: The backup filename timestamp.
  /// Side effects: None.
  /// Notes: Matches the apps' `DateFormat('yyyyMMdd_HHmmss')` output without
  /// taking an `intl` dependency.
  static String _formatStamp(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}${two(value.month)}'
        '${two(value.day)}_${two(value.hour)}${two(value.minute)}'
        '${two(value.second)}';
  }

  /// Purpose: Parse a `yyyyMMdd_HHmmss` backup filename timestamp.
  /// Inputs: [stamp] filename portion after `backup_`.
  /// Returns: The parsed local [DateTime], or null when malformed.
  /// Side effects: None.
  /// Notes: Strict shape check; callers fall back to file mtime on null,
  /// matching the apps' parse-failure fallback.
  static DateTime? _parseStamp(String stamp) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})$',
    ).firstMatch(stamp);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  /// Purpose: Create a backup now.
  /// Inputs: None.
  /// Returns: The written bundle file, or null on any failure.
  /// Side effects: Writes the bundle JSON atomically, deduplicates images
  /// into `backups/blobs/`, then runs retention cleanup and blob GC.
  /// Notes: Images are stored once per unique content hash; the bundle only
  /// records `_imageRefs` so repeated backups stay small (§J5/J6/J8).
  Future<File?> createBackup() async {
    try {
      final appDir = await storage.getAppDir();
      final backupDir = await _getBackupDir();
      final bundle = <String, dynamic>{'_backupFormat': formatVersion};

      for (final module in modules.modules) {
        final file = File(p.join(appDir.path, module.fileName));
        if (await file.exists()) {
          bundle[module.fileName] = await file.readAsString();
        }
      }

      // Deduplicate images into the shared blob store and reference them.
      final imgDir = Directory(p.join(appDir.path, _imagesDirName));
      if (await imgDir.exists()) {
        final blobDir = await _getBlobDir();
        final refs = <String, String>{};
        await for (final entity in imgDir.list()) {
          if (entity is File) {
            final bytes = await entity.readAsBytes();
            final hash = sha256.convert(bytes).toString();
            final ext = p.extension(entity.path);
            final blobName = '$hash$ext';
            final blobFile = File(p.join(blobDir.path, blobName));
            if (!await blobFile.exists()) {
              await atomicWriteBytes(blobFile, bytes);
            }
            refs['images/${p.basename(entity.path)}'] = blobName;
          }
        }
        if (refs.isNotEmpty) bundle['_imageRefs'] = refs;
      }

      final content = jsonEncode(bundle);

      final stamp = _formatStamp(_clock());
      final file = File(p.join(backupDir.path, 'backup_$stamp.json'));
      await atomicWriteString(file, content);

      await _cleanOldBackups();
      await _collectUnreferencedBlobs();
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Run auto-backup if enabled and not yet done today.
  /// Inputs: None.
  /// Returns: A future completing after the check (and possible backup).
  /// Side effects: May create a backup file and mutate `_lastAutoBackup`.
  /// Notes: Re-entrancy guarded; a corrupt (unparseable) bundle from today
  /// does not count as today's backup, so an interrupted write is retried
  /// (§J14/J15). The host owns the trigger cadence (§J21/H5).
  Future<void> runAutoBackupIfNeeded() async {
    if (_autoBackupRunning) return;
    _autoBackupRunning = true;
    try {
      await loadSettings();
      if (!autoBackupEnabled) return;

      final now = _clock();
      final today = DateTime(now.year, now.month, now.day);

      final lastAutoBackup = _lastAutoBackup;
      if (lastAutoBackup != null) {
        final lastDay = DateTime(
          lastAutoBackup.year,
          lastAutoBackup.month,
          lastAutoBackup.day,
        );
        if (!lastDay.isBefore(today)) return;
      }

      final existing = await listBackups();
      final alreadyToday = existing.any((b) {
        if (b.corrupt) return false;
        final d = b.date;
        return d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
      });
      if (alreadyToday) {
        _lastAutoBackup = now;
        return;
      }

      await createBackup();
      _lastAutoBackup = now;
    } finally {
      _autoBackupRunning = false;
    }
  }

  /// Purpose: List all backups sorted by date descending.
  /// Inputs: None.
  /// Returns: Backup info entries, newest first.
  /// Side effects: Creates `backups/` and `backups/blobs/` when missing.
  /// Notes: Small bundles are parsed to detect corruption and to add the
  /// referenced blob sizes to the displayed size; oversized legacy bundles
  /// are listed by file size alone (§J12/J13).
  Future<List<BackupInfo>> listBackups() async {
    final backupDir = await _getBackupDir();
    if (!await backupDir.exists()) return [];
    final blobDir = await _getBlobDir();

    final files = <BackupInfo>[];
    await for (final entity in backupDir.list()) {
      if (entity is File &&
          p.basename(entity.path).startsWith('backup_') &&
          entity.path.endsWith('.json')) {
        final stat = await entity.stat();
        final name = p.basenameWithoutExtension(entity.path);
        final date =
            _parseStamp(name.replaceFirst('backup_', '')) ?? stat.modified;

        var sizeBytes = stat.size;
        var corrupt = false;
        if (stat.size <= probeMaxBytes) {
          try {
            final bundle =
                jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
            final refs = bundle['_imageRefs'];
            if (refs is Map<String, dynamic>) {
              for (final blobName in refs.values) {
                if (blobName is! String) continue;
                final blobFile = File(
                  p.join(blobDir.path, p.basename(blobName)),
                );
                if (await blobFile.exists()) {
                  sizeBytes += await blobFile.length();
                }
              }
            }
          } catch (_) {
            corrupt = true;
          }
        }
        files.add(
          BackupInfo(
            file: entity,
            date: date,
            sizeBytes: sizeBytes,
            corrupt: corrupt,
          ),
        );
      }
    }
    files.sort((a, b) => b.date.compareTo(a.date));
    return files;
  }

  /// Purpose: Read a backup's content and return module ids it contains.
  /// Inputs: [file].
  /// Returns: Module ids in registry order, plus the synthetic `images`
  /// module when enabled and the bundle carries either image format.
  /// Side effects: None.
  /// Notes: Returns an empty list for unparseable bundles (§J3/J13).
  Future<List<String>> getBackupModules(File file) async {
    try {
      final raw = await file.readAsString();
      final bundle = jsonDecode(raw) as Map<String, dynamic>;
      final result = modules.modules
          .where((module) => bundle.containsKey(module.fileName))
          .map((module) => module.moduleId)
          .toList();
      if (syntheticImagesModule &&
          (bundle.containsKey('_images') || bundle.containsKey('_imageRefs'))) {
        result.add(imagesModuleId);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Purpose: Return a sanitized flat image basename or null.
  /// Inputs: [rawKey] from a backup bundle image map.
  /// Returns: The safe file basename, or null when rejected.
  /// Side effects: None.
  /// Notes: Standardized on MyDevice's tolerant form (feature-matrix §J17):
  /// accepts both bare basenames (legacy bundles) and `images/<name>` keys,
  /// rejecting traversal, nesting, and absolute paths so a crafted bundle
  /// cannot write outside `images/`.
  static String? _safeImageBasename(String rawKey) {
    var normalized = p.normalize(rawKey).replaceAll('\\', '/');
    if (normalized.startsWith('images/')) {
      normalized = normalized.substring('images/'.length);
    }
    if (normalized.isEmpty ||
        normalized.contains('/') ||
        normalized.contains('..') ||
        p.isAbsolute(normalized)) {
      return null;
    }
    return normalized;
  }

  /// Purpose: Load `webdav_config.json` for the I5 restore interplay.
  /// Inputs: None.
  /// Returns: Parsed config, or null when absent/malformed/unreadable.
  /// Side effects: Performs local file-system I/O.
  /// Notes: Mirrors the sync engine's load semantics: a missing/null
  /// `remotePath` key receives [defaultRemotePath].
  Future<WebDAVConfig?> _loadWebDavConfig() async {
    try {
      final appDir = await storage.getAppDir();
      final file = File(p.join(appDir.path, _webDavConfigFileName));
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      final json = Map<String, dynamic>.from(decoded as Map);
      if (!json.containsKey('remotePath') || json['remotePath'] == null) {
        json['remotePath'] = defaultRemotePath;
      }
      return WebDAVConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Persist `webdav_config.json` atomically.
  /// Inputs: [config].
  /// Returns: A future completing after atomic replacement.
  /// Side effects: Writes the config file.
  /// Notes: Uses compact jsonEncode, matching the apps' format.
  Future<void> _saveWebDavConfig(WebDAVConfig config) async {
    final appDir = await storage.getAppDir();
    final file = File(p.join(appDir.path, _webDavConfigFileName));
    await atomicWriteString(file, jsonEncode(config.toJson()));
  }

  /// Purpose: Re-enable auto-sync after a restore that wrote nothing.
  /// Inputs: None.
  /// Returns: A future completing after the best-effort re-enable.
  /// Side effects: May write `webdav_config.json`.
  /// Notes: Errors are swallowed: the restore result is already determined
  /// and a re-enable failure must not mask it.
  Future<void> _enableAutoSyncAfterUntouchedRestore() async {
    try {
      final config = await _loadWebDavConfig();
      if (config == null) return;
      await _saveWebDavConfig(config.copyWith(autoSync: true));
    } catch (_) {}
  }

  /// Purpose: Restore from a backup file, optionally only specific modules.
  /// Inputs: [file], [moduleKeys] module ids to restore (null = all).
  /// Returns: A [RestoreResult] describing success, whether any file was
  /// written, and how many v2 image references had no blob on disk.
  /// Side effects: When WebDAV auto-sync is enabled it is disabled in
  /// `webdav_config.json` BEFORE the first file write and re-enabled only
  /// when the restore failed without writing anything (I5, §J18). Overwrites
  /// app data files atomically and restores image files from blob references
  /// (v2) or inline base64 (legacy v1).
  /// Notes: Every selected module payload is validated through
  /// [DataModule.validate] before anything is written; image names are
  /// sanitized. With [syntheticImagesModule], images restore only when the
  /// `images` module is selected; otherwise images always restore. A failure
  /// with `wroteAnything == false` means local data is untouched.
  Future<RestoreResult> restoreBackup(
    File file, {
    Set<String>? moduleKeys,
  }) async {
    var wrote = false;
    var missingImages = 0;

    // I5: disable auto-sync before the first write; if even that fails the
    // restore must not run with auto-sync possibly still enabled.
    final bool hadAutoSync;
    try {
      final config = await _loadWebDavConfig();
      hadAutoSync = config != null && config.isConfigured && config.autoSync;
      if (hadAutoSync) {
        await _saveWebDavConfig(config.copyWith(autoSync: false));
      }
    } catch (_) {
      return const RestoreResult(ok: false, wroteAnything: false);
    }

    RestoreResult result;
    try {
      final raw = await file.readAsString();

      final bundle = jsonDecode(raw) as Map<String, dynamic>;
      final appDir = await storage.getAppDir();

      // Validate every selected payload before writing any file.
      final writes = <String, String>{};
      for (final module in modules.modules) {
        if (moduleKeys != null && !moduleKeys.contains(module.moduleId)) {
          continue;
        }
        if (!bundle.containsKey(module.fileName)) continue;
        final content = bundle[module.fileName] as String;
        module.validate(content);
        writes[module.fileName] = content;
      }

      for (final entry in writes.entries) {
        await atomicWriteString(
          File(p.join(appDir.path, entry.key)),
          entry.value,
        );
        wrote = true;
      }

      // Restore images: v2 blob references first, then legacy inline base64.
      final restoreImages =
          !syntheticImagesModule ||
          moduleKeys == null ||
          moduleKeys.contains(imagesModuleId);
      if (restoreImages) {
        final imagesDir = Directory(p.join(appDir.path, _imagesDirName));
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        final refs = bundle['_imageRefs'];
        if (refs is Map<String, dynamic>) {
          final blobDir = await _getBlobDir();
          for (final e in refs.entries) {
            final baseName = _safeImageBasename(e.key);
            final blobName = e.value;
            if (baseName == null || blobName is! String) continue;
            final blobFile = File(p.join(blobDir.path, p.basename(blobName)));
            if (!await blobFile.exists()) {
              // Blob store incomplete (e.g. bundle copied without blobs);
              // count it so the UI can warn instead of silently dropping.
              missingImages += 1;
              continue;
            }
            await atomicWriteBytes(
              File(p.join(imagesDir.path, baseName)),
              await blobFile.readAsBytes(),
            );
            wrote = true;
          }
        } else if (bundle.containsKey('_images')) {
          final imagesMap = bundle['_images'] as Map<String, dynamic>;
          for (final e in imagesMap.entries) {
            final baseName = _safeImageBasename(e.key);
            if (baseName == null || e.value is! String) continue;
            await atomicWriteBytes(
              File(p.join(imagesDir.path, baseName)),
              base64Decode(e.value as String),
            );
            wrote = true;
          }
        }
      }

      result = RestoreResult(
        ok: true,
        wroteAnything: wrote,
        missingImages: missingImages,
      );
    } catch (_) {
      result = RestoreResult(
        ok: false,
        wroteAnything: wrote,
        missingImages: missingImages,
      );
    }

    if (!result.ok && !result.wroteAnything && hadAutoSync) {
      await _enableAutoSyncAfterUntouchedRestore();
    }
    return result;
  }

  /// Purpose: Delete a specific backup.
  /// Inputs: [file].
  /// Returns: A future completing after deletion and blob GC.
  /// Side effects: Deletes the bundle, then garbage collects image blobs no
  /// remaining backup references.
  /// Notes: None.
  Future<void> deleteBackup(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
    await _collectUnreferencedBlobs();
  }

  /// Purpose: Delete bundles older than the retention window.
  /// Inputs: None.
  /// Returns: A future completing after cleanup.
  /// Side effects: Deletes expired bundle files.
  /// Notes: Internal helper; runs only inside [createBackup] (retention is
  /// age-based only, no max-count cap); 0 keeps backups forever (§J11).
  Future<void> _cleanOldBackups() async {
    if (retentionDays <= 0) return;
    final cutoff = _clock().subtract(Duration(days: retentionDays));
    final backups = await listBackups();
    for (final b in backups) {
      if (b.date.isBefore(cutoff)) {
        await b.file.delete();
      }
    }
  }

  /// Purpose: Delete image blobs that no remaining backup references.
  /// Inputs: None.
  /// Returns: A future completing after the GC pass.
  /// Side effects: Deletes files under `backups/blobs/`.
  /// Notes: Conservative: when any remaining bundle cannot be parsed the
  /// pass is aborted (the reference set is unknown, §J10), and blobs younger
  /// than [blobGcGrace] are kept so a concurrent backup write is never
  /// raced (§J9).
  Future<void> _collectUnreferencedBlobs() async {
    try {
      final blobDir = await _getBlobDir();
      final blobs = <File>[];
      await for (final entity in blobDir.list()) {
        if (entity is File) blobs.add(entity);
      }
      if (blobs.isEmpty) return;

      final backupDir = await _getBackupDir();
      final referenced = <String>{};
      await for (final entity in backupDir.list()) {
        if (entity is! File ||
            !p.basename(entity.path).startsWith('backup_') ||
            !entity.path.endsWith('.json')) {
          continue;
        }
        Map<String, dynamic> bundle;
        try {
          bundle =
              jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          // Unknown reference set: never delete blobs under uncertainty.
          return;
        }
        final refs = bundle['_imageRefs'];
        if (refs is Map<String, dynamic>) {
          for (final v in refs.values) {
            if (v is String) referenced.add(p.basename(v));
          }
        }
      }

      final now = _clock();
      for (final blob in blobs) {
        if (referenced.contains(p.basename(blob.path))) continue;
        final stat = await blob.stat();
        if (now.difference(stat.modified) < blobGcGrace) continue;
        try {
          await blob.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
