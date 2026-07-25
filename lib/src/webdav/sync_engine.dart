/// Purpose: Generic WebDAV sync orchestration for app-supplied data modules.
/// Inputs: Storage adapter, ordered module registry, WebDAV config, and hooks.
/// Returns: Sync/force results, pending conflicts, progress, and change signal.
/// Side effects: Reads and writes local data/base/lock files and remote WebDAV
/// data, images, and upload locks.
/// Notes: P2.6 preserves the feature-matrix state machine while keeping all app
/// models, file lists, migrations, and image-reference rules in DataModule.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../modules/data_module.dart';
import '../storage/atomic_io.dart';
import '../storage/storage_adapter.dart';
import 'sync_progress.dart';
import 'upload_lock.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';

/// Purpose: Build a transport client for one supplied WebDAV configuration.
/// Inputs: [config] for the current manual/background operation.
/// Returns: A bound [WebDavClient].
/// Side effects: App/test-defined.
/// Notes: Per-call config preserves syncing with unsaved config-page values.
typedef WebDavClientFactory = WebDavClient Function(WebDAVConfig config);

/// Purpose: Supply the current time for lock creation and expiry tests.
/// Inputs: None.
/// Returns: Current time; the engine normalizes it to UTC.
/// Side effects: None.
/// Notes: Defaults to DateTime.now and is injectable for deterministic tests.
typedef SyncClock = DateTime Function();

/// Purpose: Generate stable client IDs and per-upload tokens.
/// Inputs: None.
/// Returns: A unique identifier string.
/// Side effects: Generator-defined.
/// Notes: Defaults to UUID v4 and is injectable for deterministic tests.
typedef SyncIdGenerator = String Function();

/// Generic result of normal sync, force upload, or force download.
class EngineSyncResult {
  /// Purpose: Create an engine sync result.
  /// Inputs: [success], optional [error]/[pending], nonfatal [warnings].
  /// Returns: A new immutable result.
  /// Side effects: None.
  /// Notes: Conflicts may coexist with success; callers check [hasConflicts].
  const EngineSyncResult({
    required this.success,
    this.error,
    this.pending,
    this.warnings = const [],
  });

  /// Whether all fatal/per-file engine work succeeded.
  final bool success;

  /// Joined fatal or per-file error text, if any.
  final String? error;

  /// Opaque pending module merges with unresolved conflicts.
  final EnginePendingSync? pending;

  /// Nonfatal image transfer/listing warnings.
  final List<String> warnings;

  /// Purpose: Return whether unresolved module conflicts are present.
  /// Inputs: None.
  /// Returns: True when [pending] is non-null.
  /// Side effects: None.
  /// Notes: Mirrors all three apps' existing SyncResult.hasConflicts behavior.
  bool get hasConflicts => pending != null;
}

/// One pending module merge retained for later user resolution.
class EnginePendingModule {
  /// Purpose: Create pending state for one module.
  /// Inputs: [module] descriptor and its pending [outcome].
  /// Returns: A new immutable pending module.
  /// Side effects: None.
  /// Notes: The outcome retains the app's opaque typed merge state.
  const EnginePendingModule({required this.module, required this.outcome});

  /// App-owned module descriptor.
  final DataModule module;

  /// Pending merge outcome and resolver.
  final ModuleMergeOutcome outcome;

  /// Purpose: Expose the app-owned typed merge state to a P3 facade.
  /// Inputs: None.
  /// Returns: Opaque state supplied by the module merge callback.
  /// Side effects: None.
  /// Notes: The shared engine never inspects this value.
  Object? get state => outcome.state;
}

/// Ordered pending sync state spanning one or more modules.
class EnginePendingSync {
  /// Purpose: Create immutable pending sync state.
  /// Inputs: [modules] in registry/sync order.
  /// Returns: A new pending state.
  /// Side effects: None.
  /// Notes: Pending state is intentionally in-memory only, matching the apps.
  EnginePendingSync(Iterable<EnginePendingModule> modules)
    : modules = List<EnginePendingModule>.unmodifiable(modules);

  /// Pending modules in behaviorally significant registry order.
  final List<EnginePendingModule> modules;

  /// Purpose: Flatten conflicts in module and callback order.
  /// Inputs: None.
  /// Returns: A newly allocated conflict list.
  /// Side effects: None.
  /// Notes: Facades can rebuild their existing typed allConflicts views.
  List<ModuleConflict> get allConflicts => [
    for (final module in modules) ...module.outcome.conflicts,
  ];

  /// Purpose: Look up pending state by persisted module ID.
  /// Inputs: [moduleId].
  /// Returns: Matching pending module, or null.
  /// Side effects: None.
  /// Notes: IDs are unique because ModuleRegistry validates them.
  EnginePendingModule? forModuleId(String moduleId) {
    for (final module in modules) {
      if (module.module.moduleId == moduleId) return module;
    }
    return null;
  }
}

/// Generic sync engine parameterized by app-owned storage and data modules.
class WebDavSyncEngine {
  /// Purpose: Create a generic WebDAV sync engine.
  /// Inputs: [storage], ordered [modules], [defaultRemotePath], optional
  /// download policy and deterministic client/clock/ID seams.
  /// Returns: A new engine instance.
  /// Side effects: Creates a progress notifier.
  /// Notes: One long-lived instance per app preserves the operation guard,
  /// sticky local-change flag, and progress state used by existing facades.
  WebDavSyncEngine({
    required this.storage,
    required this.modules,
    required this.defaultRemotePath,
    this.failFastOnDownloadError = false,
    WebDavClientFactory? clientFactory,
    SyncClock? clock,
    SyncIdGenerator? idGenerator,
  }) : _clientFactory = clientFactory ?? ((config) => WebDavClient(config)),
       _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? (() => const Uuid().v4());

  static const _configFileName = 'webdav_config.json';
  static const _syncBaseDirName = '.sync_base';
  static const _clientIdFileName = 'client_id.txt';
  static const _localLockFileName = 'upload_lock.json';
  static const _imagesDirName = 'images';

  /// App-supplied active storage root.
  final StorageAdapter storage;

  /// Ordered app module registry.
  final ModuleRegistry modules;

  /// Per-app fallback path used only when persisted `remotePath` is absent.
  final String defaultRemotePath;

  /// Whether a normal-sync download error aborts immediately.
  final bool failFastOnDownloadError;

  final WebDavClientFactory _clientFactory;
  final SyncClock _clock;
  final SyncIdGenerator _idGenerator;

  bool _syncing = false;
  bool _localDataChanged = false;

  /// Live progress for normal sync and force operations.
  final ValueNotifier<SyncProgress> progress = ValueNotifier(SyncProgress.idle);

  /// Purpose: Read and reset the sticky local-data-changed signal.
  /// Inputs: None.
  /// Returns: Whether unconsumed engine work changed local data or images.
  /// Side effects: Resets the internal flag to false.
  /// Notes: The flag means "since last consume," not only the last operation.
  bool consumeLocalDataChanged() {
    final changed = _localDataChanged;
    _localDataChanged = false;
    return changed;
  }

  /// Purpose: Load `webdav_config.json` from the active app directory.
  /// Inputs: None.
  /// Returns: Parsed config, or null when absent/malformed/unreadable.
  /// Side effects: Performs local file-system I/O.
  /// Notes: Missing/null `remotePath` receives [defaultRemotePath]; an explicit
  /// empty string remains empty because it can mean the WebDAV account root.
  Future<WebDAVConfig?> loadConfig() async {
    try {
      final appDir = await storage.getAppDir();
      final file = File(p.join(appDir.path, _configFileName));
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

  /// Purpose: Save `webdav_config.json` in the active app directory.
  /// Inputs: [config].
  /// Returns: A future completing after atomic replacement.
  /// Side effects: Writes plaintext WebDAV credentials, matching current apps.
  /// Notes: Uses compact jsonEncode to preserve the existing config format.
  Future<void> saveConfig(WebDAVConfig config) async {
    final appDir = await storage.getAppDir();
    final file = File(p.join(appDir.path, _configFileName));
    await atomicWriteString(file, jsonEncode(config.toJson()));
  }

  /// Purpose: Delete `webdav_config.json` when present.
  /// Inputs: None.
  /// Returns: A future completing after deletion/no-op.
  /// Side effects: Performs local file-system I/O.
  /// Notes: Base snapshots, client ID, and lock metadata are left unchanged.
  Future<void> deleteConfig() async {
    final appDir = await storage.getAppDir();
    final file = File(p.join(appDir.path, _configFileName));
    if (await file.exists()) await file.delete();
  }

  /// Purpose: Test a supplied WebDAV configuration.
  /// Inputs: [config], including unsaved config-page values.
  /// Returns: True for reachable HTTP 207/404 responses.
  /// Side effects: Performs network I/O.
  /// Notes: Delegates to the P2.5 transport client.
  Future<bool> testConnection(WebDAVConfig config) {
    return _clientFactory(config).testConnection();
  }

  /// Purpose: Run normal lock-protected multi-module synchronization.
  /// Inputs: [config], [autoResolve] (default false per invariant I4).
  /// Returns: Sync result with optional pending conflicts and image warnings.
  /// Side effects: Performs local and remote I/O and updates [progress].
  /// Notes: Lock acquisition precedes every module download.
  Future<EngineSyncResult> sync(
    WebDAVConfig config, {
    bool autoResolve = false,
  }) async {
    if (_syncing) {
      return const EngineSyncResult(
        success: false,
        error: 'Sync already in progress',
      );
    }
    _syncing = true;
    _reportProgress(SyncPhase.connecting);
    try {
      final result = await _syncLocked(config, autoResolve: autoResolve);
      _reportProgress(
        result.success ? SyncPhase.done : SyncPhase.error,
        detail: result.error,
      );
      return result;
    } finally {
      _syncing = false;
    }
  }

  /// Purpose: Upload complete user-resolved pending module JSON.
  /// Inputs: [config], [pending], and per-module [resolutionsByModule].
  /// Returns: True only when every pending module finalizes successfully.
  /// Side effects: Reacquires a remote lock and may write local/remote/base data.
  /// Notes: Preserves current behavior: no shared `_syncing` guard or progress,
  /// fresh remote GET protects against unreadable state but does not re-merge.
  Future<bool> finalizePendingSync(
    WebDAVConfig config,
    EnginePendingSync pending,
    Map<String, Map<String, Object?>> resolutionsByModule,
  ) async {
    final client = _clientFactory(config);
    Directory? appDir;
    UploadSession? session;
    try {
      appDir = await storage.getAppDir();
      final clientId = await _loadClientId(appDir);
      final prepared = await _prepareInterruptedUpload(
        client,
        appDir,
        clientId,
      );
      if (prepared.error != null) return false;
      final acquired = await _acquireUploadSession(
        client,
        appDir,
        clientId,
        resumeToken: prepared.resumeToken,
      );
      session = acquired.session;
      if (session == null) return false;

      var allSucceeded = true;
      for (final pendingModule in pending.modules) {
        final module = pendingModule.module;
        var resolved = await pendingModule.outcome.resolve(
          resolutionsByModule[module.moduleId] ?? const {},
        );
        final postMerge = module.postMergeTransform;
        if (postMerge != null) resolved = await postMerge(resolved);
        final succeeded = await _finalizeModule(
          client,
          appDir,
          session,
          module,
          resolved,
        );
        if (!succeeded) allSucceeded = false;
      }
      return allSucceeded;
    } catch (_) {
      return false;
    } finally {
      await _releaseUploadSession(client, appDir: appDir, session: session);
    }
  }

  /// Purpose: Force-upload every existing local module without merge.
  /// Inputs: [config].
  /// Returns: Result with nonfatal image warnings.
  /// Side effects: Acquires the upload lock, writes remote files and bases.
  /// Notes: Missing local modules are skipped; remote files are never deleted.
  Future<EngineSyncResult> forceUpload(WebDAVConfig config) async {
    if (_syncing) {
      return const EngineSyncResult(
        success: false,
        error: 'Sync already in progress',
      );
    }
    _syncing = true;
    _reportProgress(SyncPhase.connecting);
    try {
      final result = await _forceUploadLocked(config);
      _reportProgress(
        result.success ? SyncPhase.done : SyncPhase.error,
        detail: result.error,
      );
      return result;
    } finally {
      _syncing = false;
    }
  }

  /// Purpose: Force-download remote modules without merge or remote lock.
  /// Inputs: [config].
  /// Returns: Result with missing-file and image warnings.
  /// Side effects: Replaces local data/base files and downloads missing images.
  /// Notes: Validation remains syntax-only jsonDecode for compatibility.
  Future<EngineSyncResult> forceDownload(WebDAVConfig config) async {
    if (_syncing) {
      return const EngineSyncResult(
        success: false,
        error: 'Sync already in progress',
      );
    }
    _syncing = true;
    _reportProgress(SyncPhase.connecting);
    try {
      final result = await _forceDownloadLocked(config);
      _reportProgress(
        result.success ? SyncPhase.done : SyncPhase.error,
        detail: result.error,
      );
      return result;
    } finally {
      _syncing = false;
    }
  }

  /// Purpose: Publish one progress snapshot.
  /// Inputs: [phase], optional [detail], [current], and [total].
  /// Returns: None.
  /// Side effects: Updates [progress].
  /// Notes: Terminal done/error snapshots remain until the next operation.
  void _reportProgress(
    SyncPhase phase, {
    String? detail,
    int current = 0,
    int total = 0,
  }) {
    progress.value = SyncProgress(
      phase,
      detail: detail,
      current: current,
      total: total,
    );
  }

  /// Purpose: Execute the normal sync body while a remote lock is held.
  /// Inputs: [config], [autoResolve].
  /// Returns: Aggregated sync result.
  /// Side effects: Performs all normal-sync local and remote I/O.
  /// Notes: Session release runs in finally and can surface local cleanup I/O
  /// errors, matching the existing service structure.
  Future<EngineSyncResult> _syncLocked(
    WebDAVConfig config, {
    required bool autoResolve,
  }) async {
    final client = _clientFactory(config);
    Directory? appDir;
    UploadSession? session;
    try {
      await client.ensureRemoteDir();
      appDir = await storage.getAppDir();
      final clientId = await _loadClientId(appDir);
      final prepared = await _prepareInterruptedUpload(
        client,
        appDir,
        clientId,
      );
      if (prepared.error != null) {
        return EngineSyncResult(success: false, error: prepared.error);
      }
      final acquired = await _acquireUploadSession(
        client,
        appDir,
        clientId,
        resumeToken: prepared.resumeToken,
      );
      session = acquired.session;
      if (session == null) {
        return EngineSyncResult(
          success: false,
          error: acquired.error ?? 'Upload lock was not acquired',
        );
      }

      final errors = <String>[];
      final pendingModules = <EnginePendingModule>[];
      final localForImages = <DataModule, String>{};
      final remoteForImages = <DataModule, String>{};

      for (var index = 0; index < modules.modules.length; index++) {
        final module = modules.modules[index];
        final name = module.fileName;
        _reportProgress(
          SyncPhase.downloadingData,
          detail: name,
          current: index + 1,
          total: modules.modules.length,
        );
        final localFile = File(p.join(appDir.path, name));
        final localExists = await localFile.exists();
        final remote = await client.download(name);

        if (remote.status == RemoteFileStatus.error) {
          final error = '$name: download failed: ${remote.error}';
          if (failFastOnDownloadError) {
            return EngineSyncResult(success: false, error: error);
          }
          errors.add(error);
          continue;
        }

        if (!localExists) {
          if (remote.status == RemoteFileStatus.notFound) continue;
          final remoteRaw = remote.content!;
          remoteForImages[module] = remoteRaw;
          await atomicWriteString(localFile, remoteRaw);
          await _saveBase(appDir, name, remoteRaw);
          localForImages[module] = remoteRaw;
          _localDataChanged = true;
          continue;
        }

        final localRaw = await localFile.readAsString();
        localForImages[module] = localRaw;
        if (remote.status == RemoteFileStatus.notFound) {
          _reportProgress(
            SyncPhase.uploadingData,
            detail: name,
            current: index + 1,
            total: modules.modules.length,
          );
          final uploaded = await _uploadWithSession(
            client,
            appDir,
            session,
            name,
            localRaw,
          );
          if (uploaded.error != null) {
            errors.add('$name: force-upload failed: ${uploaded.error}');
            continue;
          }
          await _saveBase(appDir, name, localRaw);
          continue;
        }

        final remoteRaw = remote.content!;
        remoteForImages[module] = remoteRaw;
        if (localRaw == remoteRaw) {
          await _saveBase(appDir, name, localRaw);
          continue;
        }

        final baseRaw = await _readBase(appDir, name);
        _reportProgress(
          SyncPhase.merging,
          detail: name,
          current: index + 1,
          total: modules.modules.length,
        );
        try {
          var currentLocal = localRaw;
          var outcome = await module.merge(
            localJson: currentLocal,
            remoteJson: remoteRaw,
            baseJson: baseRaw,
            autoResolve: autoResolve,
          );
          if (outcome.conflicts.isEmpty) {
            final latestLocal = await localFile.readAsString();
            if (latestLocal != currentLocal) {
              currentLocal = latestLocal;
              localForImages[module] = currentLocal;
              outcome = await module.merge(
                localJson: currentLocal,
                remoteJson: remoteRaw,
                baseJson: baseRaw,
                autoResolve: autoResolve,
              );
            }
          }

          if (outcome.conflicts.isNotEmpty) {
            pendingModules.add(
              EnginePendingModule(module: module, outcome: outcome),
            );
            continue;
          }

          var mergedJson = outcome.mergedJson!;
          final postMerge = module.postMergeTransform;
          if (postMerge != null) mergedJson = await postMerge(mergedJson);
          final preUpload = module.preUploadTransform;
          if (preUpload != null) {
            mergedJson = await preUpload(
              ModuleUploadContext(
                nextJson: mergedJson,
                baseJson: baseRaw,
                localJson: currentLocal,
                remoteJson: remoteRaw,
                reason: ModuleWriteReason.merge,
              ),
            );
          }

          await atomicWriteString(localFile, mergedJson);
          localForImages[module] = mergedJson;
          _localDataChanged = true;
          _reportProgress(
            SyncPhase.uploadingData,
            detail: name,
            current: module.indexMergedUploadProgress ? index + 1 : 0,
            total: module.indexMergedUploadProgress
                ? modules.modules.length
                : 0,
          );
          final uploaded = await _uploadWithSession(
            client,
            appDir,
            session,
            name,
            mergedJson,
          );
          if (uploaded.error != null) {
            errors.add('$name: force-upload failed: ${uploaded.error}');
            continue;
          }
          await _saveBase(appDir, name, mergedJson);
        } catch (error) {
          errors.add('$name: $error');
        }
      }

      final references = _collectReferencedImages(
        localForImages,
        remoteForImages,
      );
      final warnings = await _syncImages(client, appDir, session, references);
      final error = errors.isEmpty ? null : errors.join('; ');
      return EngineSyncResult(
        success: errors.isEmpty,
        error: error,
        pending: pendingModules.isEmpty
            ? null
            : EnginePendingSync(pendingModules),
        warnings: warnings,
      );
    } catch (error, stackTrace) {
      return EngineSyncResult(success: false, error: '$error\n$stackTrace');
    } finally {
      await _releaseUploadSession(client, appDir: appDir, session: session);
    }
  }

  /// Purpose: Execute force upload while holding a remote upload lock.
  /// Inputs: [config].
  /// Returns: Force-upload result.
  /// Side effects: Writes remote modules/images and local base snapshots.
  /// Notes: Data-file failure aborts later modules; image failures are warnings.
  Future<EngineSyncResult> _forceUploadLocked(WebDAVConfig config) async {
    final client = _clientFactory(config);
    Directory? appDir;
    UploadSession? session;
    try {
      await client.ensureRemoteDir();
      appDir = await storage.getAppDir();
      final clientId = await _loadClientId(appDir);
      final prepared = await _prepareInterruptedUpload(
        client,
        appDir,
        clientId,
      );
      if (prepared.error != null) {
        return EngineSyncResult(success: false, error: prepared.error);
      }
      final acquired = await _acquireUploadSession(
        client,
        appDir,
        clientId,
        resumeToken: prepared.resumeToken,
      );
      session = acquired.session;
      if (session == null) {
        return EngineSyncResult(
          success: false,
          error: acquired.error ?? 'Upload lock was not acquired',
        );
      }

      final localForImages = <DataModule, String>{};
      for (var index = 0; index < modules.modules.length; index++) {
        final module = modules.modules[index];
        final file = File(p.join(appDir.path, module.fileName));
        if (!await file.exists()) continue;
        final localRaw = await file.readAsString();
        localForImages[module] = localRaw;
        _reportProgress(
          SyncPhase.uploadingData,
          detail: module.fileName,
          current: index + 1,
          total: modules.modules.length,
        );
        final uploaded = await _uploadWithSession(
          client,
          appDir,
          session,
          module.fileName,
          localRaw,
        );
        if (uploaded.error != null) {
          return EngineSyncResult(
            success: false,
            error:
                'Failed to force-upload ${module.fileName}: ${uploaded.error}',
          );
        }
        await _saveBase(appDir, module.fileName, localRaw);
      }

      final warnings = await _forceUploadImages(
        client,
        appDir,
        session,
        _collectReferencedImages(localForImages, const {}),
      );
      return EngineSyncResult(success: true, warnings: warnings);
    } catch (error) {
      return EngineSyncResult(success: false, error: '$error');
    } finally {
      await _releaseUploadSession(client, appDir: appDir, session: session);
    }
  }

  /// Purpose: Execute lock-free force download.
  /// Inputs: [config].
  /// Returns: Force-download result.
  /// Side effects: Replaces local modules/bases and downloads missing images.
  /// Notes: Earlier module writes are retained if a later module fails.
  Future<EngineSyncResult> _forceDownloadLocked(WebDAVConfig config) async {
    final client = _clientFactory(config);
    try {
      final appDir = await storage.getAppDir();
      final warnings = <String>[];
      final remoteForImages = <DataModule, String>{};
      for (var index = 0; index < modules.modules.length; index++) {
        final module = modules.modules[index];
        final name = module.fileName;
        _reportProgress(
          SyncPhase.downloadingData,
          detail: name,
          current: index + 1,
          total: modules.modules.length,
        );
        final remote = await client.download(name);
        if (remote.status == RemoteFileStatus.error) {
          return EngineSyncResult(
            success: false,
            error: 'Failed to download $name from remote: ${remote.error}',
            warnings: warnings,
          );
        }
        if (remote.status == RemoteFileStatus.notFound) {
          warnings.add('$name: not found on remote; local file kept');
          continue;
        }
        final remoteRaw = remote.content!;
        try {
          jsonDecode(remoteRaw);
        } catch (_) {
          return EngineSyncResult(
            success: false,
            error: '$name: remote content is not valid JSON',
            warnings: warnings,
          );
        }
        final file = File(p.join(appDir.path, name));
        await atomicWriteString(file, remoteRaw);
        await _saveBase(appDir, name, remoteRaw);
        remoteForImages[module] = remoteRaw;
        _localDataChanged = true;
      }

      warnings.addAll(
        await _forceDownloadImages(
          client,
          appDir,
          _collectReferencedImages(const {}, remoteForImages),
        ),
      );
      return EngineSyncResult(success: true, warnings: warnings);
    } catch (error) {
      return EngineSyncResult(success: false, error: '$error');
    }
  }

  /// Purpose: Finalize one pending module under a freshly acquired lock.
  /// Inputs: Client, [appDir], [session], [module], complete [resolvedJson].
  /// Returns: False for remote-read or upload failure; true on full success.
  /// Side effects: Writes local data, remote data, and base snapshot.
  /// Notes: Fresh remote content is used only by optional preservation; known
  /// fields are not re-merged, matching current MyDay/MyDevice finalization.
  Future<bool> _finalizeModule(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
    DataModule module,
    String resolvedJson,
  ) async {
    final file = File(p.join(appDir.path, module.fileName));
    final preUpload = module.preUploadTransform;
    final localRaw = preUpload != null && await file.exists()
        ? await file.readAsString()
        : null;
    final remote = await client.download(module.fileName);
    if (remote.status == RemoteFileStatus.error) return false;
    var finalJson = resolvedJson;
    if (preUpload != null) {
      finalJson = await preUpload(
        ModuleUploadContext(
          nextJson: finalJson,
          baseJson: null,
          localJson: localRaw,
          remoteJson: remote.status == RemoteFileStatus.found
              ? remote.content
              : null,
          reason: ModuleWriteReason.finalize,
        ),
      );
    }
    await atomicWriteString(file, finalJson);
    _localDataChanged = true;
    final uploaded = await _uploadWithSession(
      client,
      appDir,
      session,
      module.fileName,
      finalJson,
    );
    if (uploaded.error != null) return false;
    await _saveBase(appDir, module.fileName, finalJson);
    return true;
  }

  /// Purpose: Collect referenced image names from local and remote snapshots.
  /// Inputs: Per-module [local] and [remote] JSON maps.
  /// Returns: Union of app-provided image basenames.
  /// Side effects: Invokes app callbacks.
  /// Notes: Extraction errors are ignored, matching app helpers that return
  /// empty sets for malformed payloads.
  Set<String> _collectReferencedImages(
    Map<DataModule, String> local,
    Map<DataModule, String> remote,
  ) {
    final names = <String>{};
    for (final module in modules.modules) {
      final extractor = module.referencedImages;
      if (extractor == null) continue;
      for (final raw in [local[module], remote[module]]) {
        if (raw == null) continue;
        try {
          names.addAll(extractor(raw));
        } catch (_) {
          // A malformed module contributes no image references.
        }
      }
    }
    return names;
  }

  /// Purpose: Synchronize referenced images additively in both directions.
  /// Inputs: Client, local [appDir], held [session], [references].
  /// Returns: Nonfatal image warnings.
  /// Side effects: Creates image directories and transfers missing files.
  /// Notes: Listing failure skips the entire image phase; same-name images and
  /// orphans are never overwritten or deleted.
  Future<List<String>> _syncImages(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
    Set<String> references,
  ) async {
    if (references.isEmpty) return const [];
    final imageDir = Directory(p.join(appDir.path, _imagesDirName));
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    await client.ensureRemoteSubDir(_imagesDirName);
    final localFiles = await _referencedLocalFiles(imageDir, references);
    final localNames = localFiles.map((file) => p.basename(file.path)).toSet();
    final remoteNames = await client.listSubDir(_imagesDirName);
    if (remoteNames == null) {
      return const [
        'Image sync skipped: could not list the remote images directory',
      ];
    }

    final warnings = <String>[];
    final toUpload = localFiles
        .where((file) => !remoteNames.contains(p.basename(file.path)))
        .toList();
    for (var index = 0; index < toUpload.length; index++) {
      final file = toUpload[index];
      final name = p.basename(file.path);
      _reportProgress(
        SyncPhase.uploadingImages,
        detail: name,
        current: index + 1,
        total: toUpload.length,
      );
      try {
        await _uploadBytesWithSession(
          client,
          appDir,
          session,
          '$_imagesDirName/$name',
          await file.readAsBytes(),
        );
      } on TimeoutException {
        warnings.add('Upload timed out: $name');
      } catch (error) {
        warnings.add('Upload failed for $name: $error');
      }
    }

    final toDownload = references
        .where(
          (name) => remoteNames.contains(name) && !localNames.contains(name),
        )
        .toList();
    for (var index = 0; index < toDownload.length; index++) {
      final name = toDownload[index];
      _reportProgress(
        SyncPhase.downloadingImages,
        detail: name,
        current: index + 1,
        total: toDownload.length,
      );
      try {
        final bytes = await client.downloadBytes('$_imagesDirName/$name');
        await File(p.join(imageDir.path, name)).writeAsBytes(bytes);
        _localDataChanged = true;
      } on TimeoutException {
        warnings.add('Download timed out: $name');
      } catch (error) {
        warnings.add('Download failed for $name: $error');
      }
    }
    return warnings;
  }

  /// Purpose: Upload referenced local images missing from the remote.
  /// Inputs: Client, [appDir], held [session], [references].
  /// Returns: Nonfatal upload warnings.
  /// Side effects: Performs additive remote image uploads.
  /// Notes: A listing failure treats the remote set as unknown/empty and
  /// uploads all referenced local files, matching force-upload behavior.
  Future<List<String>> _forceUploadImages(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
    Set<String> references,
  ) async {
    if (references.isEmpty) return const [];
    final imageDir = Directory(p.join(appDir.path, _imagesDirName));
    if (!await imageDir.exists()) return const [];
    await client.ensureRemoteSubDir(_imagesDirName);
    final localFiles = await _referencedLocalFiles(imageDir, references);
    final remoteNames =
        await client.listSubDir(_imagesDirName) ?? const <String>{};
    final toUpload = localFiles
        .where((file) => !remoteNames.contains(p.basename(file.path)))
        .toList();
    final warnings = <String>[];
    for (var index = 0; index < toUpload.length; index++) {
      final file = toUpload[index];
      final name = p.basename(file.path);
      _reportProgress(
        SyncPhase.uploadingImages,
        detail: name,
        current: index + 1,
        total: toUpload.length,
      );
      try {
        await _uploadBytesWithSession(
          client,
          appDir,
          session,
          '$_imagesDirName/$name',
          await file.readAsBytes(),
        );
      } on TimeoutException {
        warnings.add('Upload timed out: $name');
      } catch (error) {
        warnings.add('Upload failed for $name: $error');
      }
    }
    return warnings;
  }

  /// Purpose: Download referenced remote images missing locally.
  /// Inputs: Client, [appDir], [references] from downloaded remote modules.
  /// Returns: Nonfatal download/listing warnings.
  /// Side effects: Creates local images and downloads missing files.
  /// Notes: Force download is lock-free and never overwrites same-name images.
  Future<List<String>> _forceDownloadImages(
    WebDavClient client,
    Directory appDir,
    Set<String> references,
  ) async {
    if (references.isEmpty) return const [];
    final imageDir = Directory(p.join(appDir.path, _imagesDirName));
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    final remoteNames = await client.listSubDir(_imagesDirName);
    if (remoteNames == null) {
      return const [
        'Image download skipped: could not list the remote images directory',
      ];
    }
    final localFiles = await _referencedLocalFiles(imageDir, references);
    final localNames = localFiles.map((file) => p.basename(file.path)).toSet();
    final toDownload = references
        .where(
          (name) => remoteNames.contains(name) && !localNames.contains(name),
        )
        .toList();
    final warnings = <String>[];
    for (var index = 0; index < toDownload.length; index++) {
      final name = toDownload[index];
      _reportProgress(
        SyncPhase.downloadingImages,
        detail: name,
        current: index + 1,
        total: toDownload.length,
      );
      try {
        final bytes = await client.downloadBytes('$_imagesDirName/$name');
        await File(p.join(imageDir.path, name)).writeAsBytes(bytes);
        _localDataChanged = true;
      } on TimeoutException {
        warnings.add('Download timed out: $name');
      } catch (error) {
        warnings.add('Download failed for $name: $error');
      }
    }
    return warnings;
  }

  /// Purpose: Enumerate direct local files referenced by module JSON.
  /// Inputs: [imageDir], [references].
  /// Returns: Referenced direct child files in filesystem enumeration order.
  /// Side effects: Reads the image directory.
  /// Notes: Orphans and nested entries are ignored.
  Future<List<File>> _referencedLocalFiles(
    Directory imageDir,
    Set<String> references,
  ) async {
    final files = <File>[];
    await for (final entity in imageDir.list()) {
      if (entity is File && references.contains(p.basename(entity.path))) {
        files.add(entity);
      }
    }
    return files;
  }

  /// Purpose: Resolve/create the local `.sync_base` directory.
  /// Inputs: [appDir].
  /// Returns: Existing or newly created base directory.
  /// Side effects: May create `.sync_base`.
  /// Notes: Shared by base, client ID, and local upload-lock helpers.
  Future<Directory> _getBaseDir(Directory appDir) async {
    final directory = Directory(p.join(appDir.path, _syncBaseDirName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  /// Purpose: Read one last-successful base snapshot.
  /// Inputs: [appDir], [fileName].
  /// Returns: Raw base text, or null for absence/read failure.
  /// Side effects: Performs local file-system I/O.
  /// Notes: Read errors intentionally become first-sync/no-base semantics.
  Future<String?> _readBase(Directory appDir, String fileName) async {
    try {
      final baseDir = await _getBaseDir(appDir);
      final file = File(p.join(baseDir.path, fileName));
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Atomically save one last-successful base snapshot.
  /// Inputs: [appDir], [fileName], raw [content].
  /// Returns: A future completing after replacement.
  /// Side effects: Writes `.sync_base/<fileName>`.
  /// Notes: Call only after the branch's required upload/local write succeeds.
  Future<void> _saveBase(
    Directory appDir,
    String fileName,
    String content,
  ) async {
    final baseDir = await _getBaseDir(appDir);
    await atomicWriteString(File(p.join(baseDir.path, fileName)), content);
  }

  /// Purpose: Load or create the stable local WebDAV client ID.
  /// Inputs: [appDir].
  /// Returns: Existing trimmed nonempty ID or a generated ID.
  /// Side effects: May write `.sync_base/client_id.txt`.
  /// Notes: Existing arbitrary nonempty text is accepted for compatibility.
  Future<String> _loadClientId(Directory appDir) async {
    final baseDir = await _getBaseDir(appDir);
    final file = File(p.join(baseDir.path, _clientIdFileName));
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    final id = _idGenerator();
    await atomicWriteString(file, id);
    return id;
  }

  /// Purpose: Read a local interrupted-upload marker.
  /// Inputs: [appDir].
  /// Returns: Parsed lock, or null when absent/invalid.
  /// Side effects: Performs local file-system I/O.
  /// Notes: Invalid markers are ignored and overwritten on next acquisition.
  Future<WebDAVUploadLock?> _readLocalUploadLock(Directory appDir) async {
    try {
      final baseDir = await _getBaseDir(appDir);
      final file = File(p.join(baseDir.path, _localLockFileName));
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WebDAVUploadLock.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Persist the local interrupted-upload marker.
  /// Inputs: [appDir], [lock].
  /// Returns: A future completing after atomic replacement.
  /// Side effects: Writes `.sync_base/upload_lock.json`.
  /// Notes: Remote lock is written first, matching current acquisition order.
  Future<void> _saveLocalUploadLock(
    Directory appDir,
    WebDAVUploadLock lock,
  ) async {
    final baseDir = await _getBaseDir(appDir);
    await atomicWriteString(
      File(p.join(baseDir.path, _localLockFileName)),
      jsonEncode(lock.toJson()),
    );
  }

  /// Purpose: Remove the local interrupted-upload marker when present.
  /// Inputs: [appDir].
  /// Returns: A future completing after deletion/no-op.
  /// Side effects: Deletes `.sync_base/upload_lock.json`.
  /// Notes: Delete errors propagate, matching existing finally behavior.
  Future<void> _clearLocalUploadLock(Directory appDir) async {
    final baseDir = await _getBaseDir(appDir);
    final file = File(p.join(baseDir.path, _localLockFileName));
    if (await file.exists()) await file.delete();
  }

  /// Purpose: Inspect a leftover local upload marker before acquisition.
  /// Inputs: [client], [appDir], current stable [clientId].
  /// Returns: Optional resume token or blocking error.
  /// Side effects: May clear stale local lock state.
  /// Notes: Exact matching client/token resumes even if the old lock expired.
  Future<({String? resumeToken, String? error})> _prepareInterruptedUpload(
    WebDavClient client,
    Directory appDir,
    String clientId,
  ) async {
    final localLock = await _readLocalUploadLock(appDir);
    if (localLock == null) return (resumeToken: null, error: null);
    final remote = await client.readRemoteUploadLock();
    if (remote.error != null) return (resumeToken: null, error: remote.error);
    final remoteLock = remote.lock;
    if (remoteLock == null) {
      await _clearLocalUploadLock(appDir);
      return (resumeToken: null, error: null);
    }
    final now = _clock().toUtc();
    if (remoteLock.matches(localLock.clientId, localLock.token) &&
        localLock.clientId == clientId) {
      return (resumeToken: localLock.token, error: null);
    }
    if (remoteLock.clientId != clientId && !remoteLock.isExpired(now)) {
      return (
        resumeToken: null,
        error: 'Another device is uploading; retry after the lock expires.',
      );
    }
    await _clearLocalUploadLock(appDir);
    return (resumeToken: null, error: null);
  }

  /// Purpose: Acquire or replace the remote upload lock.
  /// Inputs: [client], [appDir], stable [clientId], optional [resumeToken].
  /// Returns: Upload session or visible acquisition error.
  /// Side effects: Writes remote `.lock` then local upload marker.
  /// Notes: Active different-client locks block; HTTP 412 uses the fixed
  /// contention message and lock writes remain retry-exempt in WebDavClient.
  Future<({UploadSession? session, String? error})> _acquireUploadSession(
    WebDavClient client,
    Directory appDir,
    String clientId, {
    String? resumeToken,
  }) async {
    final now = _clock().toUtc();
    final remote = await client.readRemoteUploadLock();
    if (remote.error != null) return (session: null, error: remote.error);
    final remoteLock = remote.lock;
    if (remoteLock != null &&
        remoteLock.clientId != clientId &&
        !remoteLock.isExpired(now)) {
      return (
        session: null,
        error: 'Another device is uploading; retry after the lock expires.',
      );
    }

    final lock = WebDAVUploadLock(
      clientId: clientId,
      token: resumeToken ?? _idGenerator(),
      startedAt: now,
      updatedAt: now,
      ttlSeconds: client.lockTtlSeconds,
    );
    final write = await client.writeRemoteUploadLock(
      lock,
      ifMatchEtag: remote.etag,
      ifNoneMatchAll: remoteLock == null && remote.etag == null,
    );
    if (write.error != null) {
      return (
        session: null,
        error: write.is412
            ? 'Another device started uploading; retry after the lock expires.'
            : write.error,
      );
    }
    await _saveLocalUploadLock(appDir, lock);
    return (
      session: UploadSession(clientId: clientId, token: lock.token),
      error: null,
    );
  }

  /// Purpose: Refresh ownership of a held upload session.
  /// Inputs: [client], [appDir], [session].
  /// Returns: Null on success or a visible lock error.
  /// Side effects: Rewrites remote and local lock timestamps.
  /// Notes: Same-client/different-token locks remain replaceable for parity.
  Future<String?> _refreshUploadLock(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
  ) async {
    final remote = await client.readRemoteUploadLock();
    if (remote.error != null) return remote.error;
    final now = _clock().toUtc();
    final remoteLock = remote.lock;
    if (remoteLock != null &&
        !remoteLock.matches(session.clientId, session.token) &&
        remoteLock.clientId != session.clientId &&
        !remoteLock.isExpired(now)) {
      return 'Another device is uploading; retry after the lock expires.';
    }
    final lock =
        remoteLock != null &&
            remoteLock.matches(session.clientId, session.token)
        ? remoteLock.refreshed(now)
        : WebDAVUploadLock(
            clientId: session.clientId,
            token: session.token,
            startedAt: now,
            updatedAt: now,
            ttlSeconds: client.lockTtlSeconds,
          );
    final write = await client.writeRemoteUploadLock(
      lock,
      ifMatchEtag: remote.etag,
      ifNoneMatchAll: remoteLock == null && remote.etag == null,
    );
    if (write.error != null) {
      return write.is412
          ? 'Another device started uploading; retry after the lock expires.'
          : write.error;
    }
    await _saveLocalUploadLock(appDir, lock);
    return null;
  }

  /// Purpose: Upload string data after validating and heartbeat-refreshing lock.
  /// Inputs: Client, [appDir], [session], remote [name], [content].
  /// Returns: Standard P2.5 upload result.
  /// Side effects: Refreshes lock and writes remote data.
  /// Notes: Data-file PUT has no ETag precondition; `.lock` is the guard.
  Future<({bool is412, String? error})> _uploadWithSession(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
    String name,
    String content,
  ) async {
    final lockError = await _refreshUploadLock(client, appDir, session);
    if (lockError != null) return (is412: false, error: lockError);
    return client.withLockHeartbeat(
      refreshLock: () async {
        await _refreshUploadLock(client, appDir, session);
      },
      operation: () => client.upload(name, content),
    );
  }

  /// Purpose: Upload image bytes after lock validation and heartbeat refresh.
  /// Inputs: Client, [appDir], [session], remote [name], [bytes].
  /// Returns: A future completing after upload.
  /// Side effects: Refreshes lock and writes remote image bytes.
  /// Notes: A pre-PUT lock error is thrown and rendered as an image warning.
  Future<void> _uploadBytesWithSession(
    WebDavClient client,
    Directory appDir,
    UploadSession session,
    String name,
    List<int> bytes,
  ) async {
    final lockError = await _refreshUploadLock(client, appDir, session);
    if (lockError != null) throw Exception(lockError);
    await client.withLockHeartbeat(
      refreshLock: () async {
        await _refreshUploadLock(client, appDir, session);
      },
      operation: () => client.uploadBytes(name, Uint8List.fromList(bytes)),
    );
  }

  /// Purpose: Release a held upload session and clear its local marker.
  /// Inputs: [client], optional [appDir] and [session].
  /// Returns: A future completing after cleanup/no-op.
  /// Side effects: May conditionally delete remote `.lock` and local marker.
  /// Notes: Remote delete runs only for exact client/token ownership. Remote
  /// failures are swallowed by P2.5 delete; local clear errors propagate.
  Future<void> _releaseUploadSession(
    WebDavClient client, {
    required Directory? appDir,
    required UploadSession? session,
  }) async {
    if (session == null || appDir == null) return;
    final remote = await client.readRemoteUploadLock();
    if (remote.lock?.matches(session.clientId, session.token) ?? false) {
      await client.deleteRemoteUploadLock(etag: remote.etag);
    }
    await _clearLocalUploadLock(appDir);
  }
}
