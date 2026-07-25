import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

import 'fake_webdav_server.dart';
import 'request_recorder.dart';

const _record = bool.fromEnvironment('GOLDEN_RECORD', defaultValue: false);
const _serverUrl = 'https://golden.test/dav/files/u';
final _fixedNow = DateTime(2026, 7, 24, 12);

/// One synthetic app module used by the Phase 2 transcript replay.
class _ModuleShape {
  /// Purpose: Describe one persisted module and whether it references images.
  /// Inputs: [moduleId], [fileName], and [referencesImages].
  /// Returns: A synthetic module shape.
  /// Side effects: None.
  /// Notes: Names mirror the corresponding app registry exactly.
  const _ModuleShape(
    this.moduleId,
    this.fileName, {
    this.referencesImages = false,
  });

  final String moduleId;
  final String fileName;
  final bool referencesImages;
}

/// One app-shaped registry and its persisted compatibility knobs.
class _AppShape {
  /// Purpose: Describe one synthetic app registry used by every golden scenario.
  /// Inputs: App [name], [remotePath], ordered [modules], ZIP [archivePrefix],
  /// and optional [syntheticImagesModule].
  /// Returns: An immutable app shape.
  /// Side effects: None.
  /// Notes: The three instances reproduce the 1/5/4-module app topology.
  const _AppShape({
    required this.name,
    required this.remotePath,
    required this.modules,
    required this.archivePrefix,
    required this.localChangeModuleId,
    required this.remoteChangeModuleId,
    required this.identicalChangeModuleId,
    required this.conflictModuleId,
    this.syntheticImagesModule = false,
  });

  final String name;
  final String remotePath;
  final List<_ModuleShape> modules;
  final String archivePrefix;
  final String localChangeModuleId;
  final String remoteChangeModuleId;
  final String identicalChangeModuleId;
  final String conflictModuleId;
  final bool syntheticImagesModule;

  /// Purpose: Find one module by its persisted [moduleId].
  /// Inputs: Target [moduleId].
  /// Returns: Matching module shape.
  /// Side effects: None.
  /// Notes: Shape declarations guarantee a match.
  _ModuleShape module(String moduleId) =>
      modules.singleWhere((module) => module.moduleId == moduleId);
}

const _appShapes = [
  _AppShape(
    name: 'myanime',
    remotePath: '/MyAnime',
    archivePrefix: 'myanime_export_',
    localChangeModuleId: 'anime',
    remoteChangeModuleId: 'anime',
    identicalChangeModuleId: 'anime',
    conflictModuleId: 'anime',
    modules: [_ModuleShape('anime', 'anime_data.json', referencesImages: true)],
  ),
  _AppShape(
    name: 'myday',
    remotePath: '/MyDay',
    archivePrefix: 'myday_backup_',
    localChangeModuleId: 'weight',
    remoteChangeModuleId: 'todo',
    identicalChangeModuleId: 'todo',
    conflictModuleId: 'weight',
    modules: [
      _ModuleShape('todo', 'todo_data.json'),
      _ModuleShape('finance', 'finance_data.json', referencesImages: true),
      _ModuleShape('exchangeRates', 'exchange_rates.json'),
      _ModuleShape('intimacy', 'intimacy_data.json', referencesImages: true),
      _ModuleShape('weight', 'weight_data.json'),
    ],
  ),
  _AppShape(
    name: 'mydevice',
    remotePath: '/MyDevice',
    archivePrefix: 'mydevice_export_',
    localChangeModuleId: 'devices',
    remoteChangeModuleId: 'datasets',
    identicalChangeModuleId: 'devices',
    conflictModuleId: 'devices',
    syntheticImagesModule: true,
    modules: [
      _ModuleShape('devices', 'device_data.json', referencesImages: true),
      _ModuleShape('networks', 'network_data.json'),
      _ModuleShape('datasets', 'dataset_data.json'),
      _ModuleShape('services', 'service_data.json'),
    ],
  ),
];

/// Storage adapter backed by one scenario's temporary directory.
class _GoldenStorage implements StorageAdapter {
  /// Purpose: Create temporary storage for a golden scenario.
  /// Inputs: Root [directory].
  /// Returns: A storage adapter.
  /// Side effects: None.
  /// Notes: Config remains in memory because these scenarios exercise data I/O.
  _GoldenStorage(this.directory);

  final Directory directory;
  Map<String, dynamic> config = {};

  /// Purpose: Return the scenario's isolated app directory.
  /// Inputs: None.
  /// Returns: [directory].
  /// Side effects: None.
  /// Notes: None.
  @override
  Future<Directory> getAppDir() async => directory;

  /// Purpose: Read a copy of the scenario's storage configuration.
  /// Inputs: None.
  /// Returns: A mutable config copy.
  /// Side effects: None.
  /// Notes: None.
  @override
  Future<Map<String, dynamic>> readConfig() async => Map.of(config);

  /// Purpose: Replace the scenario's storage configuration.
  /// Inputs: New [config].
  /// Returns: A completed future.
  /// Side effects: Updates in-memory state.
  /// Notes: None.
  @override
  Future<void> writeConfig(Map<String, dynamic> config) async {
    this.config = Map.of(config);
  }
}

/// Fresh local and remote state for one deterministic scenario.
class _Sandbox {
  /// Purpose: Create an isolated golden sandbox for [shape].
  /// Inputs: [shape], temporary [directory], [server], and [recorder].
  /// Returns: A scenario sandbox with all shared engines wired.
  /// Side effects: Constructs engine instances only.
  /// Notes: Every test gets a new sandbox to prevent sequence contamination.
  _Sandbox(this.shape, this.directory, this.server, this.recorder)
    : storage = _GoldenStorage(directory) {
    var nextId = 0;
    registry = ModuleRegistry(
      shape.modules.map(
        (module) => DataModule(
          fileName: module.fileName,
          moduleId: module.moduleId,
          validate: _validatePayload,
          merge: _mergePayloads,
          referencedImages: module.referencesImages ? _referencedImages : null,
        ),
      ),
    );
    syncEngine = WebDavSyncEngine(
      storage: storage,
      modules: registry,
      defaultRemotePath: shape.remotePath,
      clientFactory: (config) => WebDavClient(
        config,
        httpClient: recorder,
        retryDelay: Duration.zero,
        heartbeatInterval: const Duration(days: 1),
      ),
      clock: () => _fixedNow,
      idGenerator: () {
        nextId++;
        return '00000000-0000-4000-8000-${nextId.toString().padLeft(12, '0')}';
      },
    );
  }

  final _AppShape shape;
  final Directory directory;
  final FakeWebDAVServer server;
  final RequestRecorder recorder;
  late final _GoldenStorage storage;
  late final ModuleRegistry registry;
  late final WebDavSyncEngine syncEngine;

  /// Purpose: Build the fake-server path for remote [name].
  /// Inputs: Relative remote [name].
  /// Returns: Full request path.
  /// Side effects: None.
  /// Notes: Uses the same Nextcloud-style root as the P0.2 harness.
  String remote(String name) => '/dav/files/u${shape.remotePath}/$name';

  /// Purpose: Return this shape's fixed WebDAV configuration.
  /// Inputs: None.
  /// Returns: Config targeting the fake server.
  /// Side effects: None.
  /// Notes: Credentials are synthetic and normalized by the recorder.
  WebDAVConfig get config => WebDAVConfig(
    serverUrl: _serverUrl,
    username: 'u',
    password: 'p',
    remotePath: shape.remotePath,
  );

  /// Purpose: Write all [data] payloads to local module files.
  /// Inputs: Map keyed by module file name.
  /// Returns: A future completing after writes.
  /// Side effects: Creates and writes local files.
  /// Notes: Payload strings are already canonical JSON.
  Future<void> writeLocal(Map<String, String> data) async {
    for (final entry in data.entries) {
      await File(p.join(directory.path, entry.key)).writeAsString(entry.value);
    }
  }

  /// Purpose: Seed all [data] payloads in the fake remote store.
  /// Inputs: Map keyed by module file name.
  /// Returns: None.
  /// Side effects: Mutates [server].
  /// Notes: Seeding bypasses request recording by design.
  void seedRemote(Map<String, String> data) {
    for (final entry in data.entries) {
      server.seed(remote(entry.key), entry.value);
    }
  }

  /// Purpose: Write sync-base snapshots for all [data] payloads.
  /// Inputs: Map keyed by module file name.
  /// Returns: A future completing after writes.
  /// Side effects: Creates `.sync_base` and writes snapshots.
  /// Notes: Matches the persisted I2 layout.
  Future<void> writeBase(Map<String, String> data) async {
    final baseDir = Directory(p.join(directory.path, '.sync_base'));
    await baseDir.create(recursive: true);
    for (final entry in data.entries) {
      await File(p.join(baseDir.path, entry.key)).writeAsString(entry.value);
    }
  }

  /// Purpose: Render the recorded HTTP exchanges.
  /// Inputs: None.
  /// Returns: Normalized deterministic transcript.
  /// Side effects: None.
  /// Notes: Volatile lock values are replaced by placeholders.
  String transcript() => GoldenTranscript(recorder.exchanges).render();
}

/// Purpose: Validate the synthetic module payload schema.
/// Inputs: Raw JSON [raw].
/// Returns: None; throws for malformed payloads.
/// Side effects: None.
/// Notes: Requires record and image lists to keep backup/ZIP validation useful.
void _validatePayload(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  (decoded['records'] as List<dynamic>).cast<Map<String, dynamic>>();
  (decoded['images'] as List<dynamic>).cast<String>();
}

/// Purpose: Extract flat referenced image basenames from a synthetic payload.
/// Inputs: Raw module [raw] JSON.
/// Returns: Image-name set.
/// Side effects: None.
/// Notes: Mirrors app callbacks while keeping the fixture app-neutral.
Set<String> _referencedImages(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['images'] as List<dynamic>).cast<String>().toSet();
}

/// Purpose: Parse synthetic records into an ID-indexed map.
/// Inputs: Raw module [raw] JSON.
/// Returns: Records keyed by their stable ID.
/// Side effects: None.
/// Notes: The map preserves payload record objects for conflict resolution.
Map<String, Map<String, dynamic>> _records(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return {
    for (final record
        in (decoded['records'] as List<dynamic>).cast<Map<String, dynamic>>())
      record['id'] as String: record,
  };
}

/// Purpose: Return whether two optional JSON record maps have equal content.
/// Inputs: Optional records [left] and [right].
/// Returns: True when their encoded values match.
/// Side effects: None.
/// Notes: Synthetic maps use deterministic insertion order.
bool _recordEquals(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

/// Purpose: Encode merged records and image references as canonical JSON.
/// Inputs: ID-indexed [records] and image [images].
/// Returns: Pretty-printed complete module JSON.
/// Side effects: None.
/// Notes: IDs and image names are sorted for stable fixtures.
String _encodePayload(
  Map<String, Map<String, dynamic>> records,
  Iterable<String> images,
) {
  final recordIds = records.keys.toList()..sort();
  final imageNames = images.toSet().toList()..sort();
  return const JsonEncoder.withIndent('  ').convert({
    'records': [for (final id in recordIds) records[id]],
    'images': imageNames,
  });
}

/// Purpose: Perform a deterministic three-way merge for synthetic payloads.
/// Inputs: Local/remote/base JSON and [autoResolve].
/// Returns: Complete merged JSON or pending record conflicts.
/// Side effects: None.
/// Notes: The callback exercises engine orchestration, not app model logic.
ModuleMergeOutcome _mergePayloads({
  required String localJson,
  required String remoteJson,
  required String? baseJson,
  required bool autoResolve,
}) {
  final local = _records(localJson);
  final remote = _records(remoteJson);
  final base = baseJson == null
      ? <String, Map<String, dynamic>>{}
      : _records(baseJson);
  final ids = {...local.keys, ...remote.keys}.toList()..sort();
  final merged = <String, Map<String, dynamic>>{};
  final conflicts = <ModuleConflict>[];

  for (final id in ids) {
    final localRecord = local[id];
    final remoteRecord = remote[id];
    final baseRecord = base[id];
    if (_recordEquals(localRecord, remoteRecord)) {
      if (localRecord != null) merged[id] = localRecord;
      continue;
    }
    final localChanged = !_recordEquals(localRecord, baseRecord);
    final remoteChanged = !_recordEquals(remoteRecord, baseRecord);
    if (localChanged && !remoteChanged) {
      if (localRecord != null) merged[id] = localRecord;
    } else if (remoteChanged && !localChanged) {
      if (remoteRecord != null) merged[id] = remoteRecord;
    } else if (autoResolve) {
      if (localRecord != null) merged[id] = localRecord;
    } else {
      conflicts.add(
        ModuleConflict(
          id: id,
          resolutionKey: 'record:$id',
          localRecord: localRecord ?? const <String, dynamic>{},
          remoteRecord: remoteRecord ?? const <String, dynamic>{},
          displayName: id,
        ),
      );
    }
  }

  final localImages = _referencedImages(localJson);
  final remoteImages = _referencedImages(remoteJson);
  final images = {...localImages, ...remoteImages};
  if (conflicts.isEmpty) {
    return ModuleMergeOutcome(mergedJson: _encodePayload(merged, images));
  }
  return ModuleMergeOutcome(
    conflicts: conflicts,
    buildResolvedJson: (resolutions) {
      final resolved = Map<String, Map<String, dynamic>>.from(merged);
      for (final conflict in conflicts) {
        final choice = resolutions[conflict.resolutionKey];
        final selected = _recordEquals(choice, conflict.remoteRecord)
            ? conflict.remoteRecord
            : conflict.localRecord;
        if (selected is Map<String, dynamic> && selected.isNotEmpty) {
          resolved[conflict.id] = selected;
        }
      }
      return _encodePayload(resolved, images);
    },
  );
}

/// Purpose: Build canonical payload data for every module in [shape].
/// Inputs: [shape], default [value], and optional per-file [overrides]/[images].
/// Returns: File-name keyed JSON payloads.
/// Side effects: None.
/// Notes: Each module owns one stable synthetic record.
Map<String, String> _dataSet(
  _AppShape shape, {
  String value = 'base',
  Map<String, String> overrides = const {},
  Map<String, List<String>> images = const {},
}) {
  return {
    for (final module in shape.modules)
      module.fileName: _encodePayload({
        '${module.moduleId}-1': {
          'id': '${module.moduleId}-1',
          'value': overrides[module.fileName] ?? value,
        },
      }, images[module.fileName] ?? const []),
  };
}

/// Purpose: Create and register cleanup for one scenario sandbox.
/// Inputs: Target app [shape].
/// Returns: Fresh temporary local/server state.
/// Side effects: Creates a temporary directory and teardown callback.
/// Notes: The fake server starts empty.
Future<_Sandbox> _newSandbox(_AppShape shape) async {
  final directory = await Directory.systemTemp.createTemp(
    'myapps_data_${shape.name}_golden_',
  );
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final server = FakeWebDAVServer();
  final recorder = RequestRecorder(server);
  return _Sandbox(shape, directory, server, recorder);
}

/// Purpose: Match or record one [actual] fixture for [shape] and [scenario].
/// Inputs: App [shape], fixture [scenario], and rendered [actual].
/// Returns: A future completing after the test assertion.
/// Side effects: Reads or records a package-local golden file.
/// Notes: Verify mode is the default used by CI.
Future<void> _expectGolden(
  _AppShape shape,
  String scenario,
  String actual,
) async {
  final file = File(
    p.join('test', 'golden', 'goldens', shape.name, '$scenario.txt'),
  );
  final mismatch = await GoldenMatcher(file, record: _record).check(actual);
  expect(
    mismatch,
    isNull,
    reason: '${shape.name} golden "$scenario" mismatch:\n$mismatch',
  );
}

/// Purpose: Return sorted file entry names from ZIP [file].
/// Inputs: Exported ZIP [file].
/// Returns: Sorted flat entry-name list.
/// Side effects: Reads and decodes the archive.
/// Notes: Directory entries, if any, are excluded.
List<String> _zipEntries(File file) {
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  return archive.files
      .where((entry) => entry.isFile)
      .map((entry) => entry.name)
      .toList()
    ..sort();
}

/// Purpose: Register the complete P0.2 scenario topology for [shape].
/// Inputs: One synthetic app [shape].
/// Returns: None.
/// Side effects: Registers sync, backup, and ZIP tests.
/// Notes: Ten wire transcripts plus two on-disk format fixtures are produced.
void _registerShapeGoldens(_AppShape shape) {
  group('${shape.name} shared engines', () {
    test('first sync', () async {
      final sandbox = await _newSandbox(shape);
      final local = _dataSet(shape);
      await sandbox.writeLocal(local);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      for (final module in shape.modules) {
        expect(
          sandbox.server.readText(sandbox.remote(module.fileName)),
          local[module.fileName],
        );
      }
      await _expectGolden(shape, 'sync_first', sandbox.transcript());
    });

    test('no-change sync', () async {
      final sandbox = await _newSandbox(shape);
      final data = _dataSet(shape);
      await sandbox.writeLocal(data);
      sandbox.seedRemote(data);
      await sandbox.writeBase(data);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      await _expectGolden(shape, 'sync_no_change', sandbox.transcript());
    });

    test('local-only change', () async {
      final sandbox = await _newSandbox(shape);
      final changedFile = shape.module(shape.localChangeModuleId).fileName;
      final base = _dataSet(shape);
      final local = _dataSet(shape, overrides: {changedFile: 'local-change'});
      await sandbox.writeLocal(local);
      sandbox.seedRemote(base);
      await sandbox.writeBase(base);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      expect(
        sandbox.server.readText(sandbox.remote(changedFile)),
        contains('local-change'),
      );
      await _expectGolden(shape, 'sync_local_change', sandbox.transcript());
    });

    test('remote-only change', () async {
      final sandbox = await _newSandbox(shape);
      final changedFile = shape.module(shape.remoteChangeModuleId).fileName;
      final base = _dataSet(shape);
      final remote = _dataSet(shape, overrides: {changedFile: 'remote-change'});
      await sandbox.writeLocal(base);
      sandbox.seedRemote(remote);
      await sandbox.writeBase(base);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      expect(
        await File(p.join(sandbox.directory.path, changedFile)).readAsString(),
        contains('remote-change'),
      );
      await _expectGolden(shape, 'sync_remote_change', sandbox.transcript());
    });

    test('both changed identically', () async {
      final sandbox = await _newSandbox(shape);
      final changedFile = shape.module(shape.identicalChangeModuleId).fileName;
      final base = _dataSet(shape);
      final both = _dataSet(shape, overrides: {changedFile: 'same-change'});
      await sandbox.writeLocal(both);
      sandbox.seedRemote(both);
      await sandbox.writeBase(base);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      expect(result.pending, isNull);
      await _expectGolden(shape, 'sync_both_identical', sandbox.transcript());
    });

    test('true conflict then finalize', () async {
      final sandbox = await _newSandbox(shape);
      final changed = shape.module(shape.conflictModuleId);
      final base = _dataSet(shape);
      final local = _dataSet(
        shape,
        overrides: {changed.fileName: 'local-choice'},
      );
      final remote = _dataSet(
        shape,
        overrides: {changed.fileName: 'remote-choice'},
      );
      await sandbox.writeLocal(local);
      sandbox.seedRemote(remote);
      await sandbox.writeBase(base);

      final syncResult = await sandbox.syncEngine.sync(sandbox.config);

      expect(syncResult.success, isTrue, reason: syncResult.error);
      expect(syncResult.pending, isNotNull);
      final resolutions = <String, Map<String, Object?>>{};
      for (final pendingModule in syncResult.pending!.modules) {
        resolutions[pendingModule.module.moduleId] = {
          for (final conflict in pendingModule.outcome.conflicts)
            conflict.resolutionKey: conflict.remoteRecord,
        };
      }
      final finalized = await sandbox.syncEngine.finalizePendingSync(
        sandbox.config,
        syncResult.pending!,
        resolutions,
      );

      expect(finalized, isTrue);
      expect(
        sandbox.server.readText(sandbox.remote(changed.fileName)),
        contains('remote-choice'),
      );
      await _expectGolden(
        shape,
        'sync_conflict_finalize',
        sandbox.transcript(),
      );
    });

    test('force upload', () async {
      final sandbox = await _newSandbox(shape);
      final local = _dataSet(shape, value: 'force-local');
      final remote = _dataSet(shape, value: 'stale-remote');
      await sandbox.writeLocal(local);
      sandbox.seedRemote(remote);

      final result = await sandbox.syncEngine.forceUpload(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      for (final module in shape.modules) {
        expect(
          sandbox.server.readText(sandbox.remote(module.fileName)),
          contains('force-local'),
        );
      }
      await _expectGolden(shape, 'force_upload', sandbox.transcript());
    });

    test('force download', () async {
      final sandbox = await _newSandbox(shape);
      final local = _dataSet(shape, value: 'stale-local');
      final remote = _dataSet(shape, value: 'force-remote');
      await sandbox.writeLocal(local);
      sandbox.seedRemote(remote);

      final result = await sandbox.syncEngine.forceDownload(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      for (final module in shape.modules) {
        expect(
          await File(
            p.join(sandbox.directory.path, module.fileName),
          ).readAsString(),
          contains('force-remote'),
        );
      }
      await _expectGolden(shape, 'force_download', sandbox.transcript());
    });

    test('interrupted upload recovery', () async {
      final sandbox = await _newSandbox(shape);
      final data = _dataSet(shape);
      await sandbox.writeLocal(data);
      sandbox.seedRemote(data);
      final baseDir = Directory(p.join(sandbox.directory.path, '.sync_base'));
      await baseDir.create(recursive: true);
      await File(p.join(baseDir.path, 'upload_lock.json')).writeAsString(
        jsonEncode({
          'clientId': 'dead-client',
          'token': 'dead-token',
          'startedAt': '2026-07-01T00:00:00.000Z',
          'updatedAt': '2026-07-01T00:00:00.000Z',
          'ttlSeconds': 60,
        }),
      );

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      expect(
        await File(p.join(baseDir.path, 'upload_lock.json')).exists(),
        isFalse,
      );
      await _expectGolden(
        shape,
        'sync_interrupted_recovery',
        sandbox.transcript(),
      );
    });

    test('image add on both sides', () async {
      final sandbox = await _newSandbox(shape);
      final imageModules = shape.modules
          .where((module) => module.referencesImages)
          .toList();
      final localImageModule = imageModules.first.fileName;
      final remoteImageModule = imageModules.last.fileName;
      final local = _dataSet(
        shape,
        images: {
          localImageModule: ['local.jpg'],
        },
      );
      final remote = _dataSet(
        shape,
        images: {
          remoteImageModule: ['remote.jpg'],
        },
      );
      await sandbox.writeLocal(local);
      await sandbox.writeBase(local);
      sandbox.seedRemote(remote);
      final imageDir = Directory(p.join(sandbox.directory.path, 'images'));
      await imageDir.create(recursive: true);
      await File(p.join(imageDir.path, 'local.jpg')).writeAsBytes([1, 2, 3]);
      sandbox.server.seed(sandbox.remote('images/remote.jpg'), [9, 9, 9]);

      final result = await sandbox.syncEngine.sync(sandbox.config);

      expect(result.success, isTrue, reason: result.error);
      expect(result.warnings, isEmpty);
      expect(sandbox.server.exists(sandbox.remote('images/local.jpg')), isTrue);
      expect(await File(p.join(imageDir.path, 'remote.jpg')).exists(), isTrue);
      await _expectGolden(
        shape,
        'sync_image_add_both_sides',
        sandbox.transcript(),
      );
    });

    test('backup v2 bundle layout', () async {
      final sandbox = await _newSandbox(shape);
      await sandbox.writeLocal(_dataSet(shape));
      final image = File(
        p.join(sandbox.directory.path, 'images', 'cover1.jpg'),
      );
      await image.parent.create(recursive: true);
      await image.writeAsBytes([1, 2, 3]);
      final engine = BackupEngine(
        storage: sandbox.storage,
        modules: sandbox.registry,
        defaultRemotePath: shape.remotePath,
        syntheticImagesModule: shape.syntheticImagesModule,
        clock: () => _fixedNow,
      );

      final backup = await engine.createBackup();

      expect(backup, isNotNull);
      final bundle =
          jsonDecode(await backup!.readAsString()) as Map<String, dynamic>;
      final blobDir = Directory(
        p.join(sandbox.directory.path, 'backups', 'blobs'),
      );
      final blobs = await blobDir
          .list()
          .where((entity) => entity is File)
          .map((entity) => p.basename(entity.path))
          .toList();
      blobs.sort();
      final dataIsString = shape.modules.length == 1
          ? '${bundle[shape.modules.single.fileName] is String}'
          : shape.modules
                .map(
                  (module) =>
                      '${module.fileName}=${bundle[module.fileName] is String}',
                )
                .join(',');
      final actual = StringBuffer()
        ..writeln('backupFormat: ${bundle['_backupFormat']}')
        ..writeln('topLevelKeys: ${(bundle.keys.toList()..sort()).join(',')}')
        ..writeln('hasImageRefs: ${bundle.containsKey('_imageRefs')}')
        ..writeln(
          'imageRefKeys: ${((bundle['_imageRefs'] as Map?)?.keys.toList() ?? [])}',
        )
        ..writeln('dataIsString: $dataIsString')
        ..writeln(
          'blobs: ${blobs.map((name) => name.replaceAll(RegExp('[0-9a-f]{64}'), '<sha256>')).join(',')}',
        );
      await _expectGolden(shape, 'backup_v2_create', actual.toString());
    });

    test('ZIP export entry list', () async {
      final sandbox = await _newSandbox(shape);
      await sandbox.writeLocal(_dataSet(shape));
      final image = File(
        p.join(sandbox.directory.path, 'images', 'cover1.jpg'),
      );
      await image.parent.create(recursive: true);
      await image.writeAsBytes([1, 2, 3]);
      final output = await Directory.systemTemp.createTemp(
        'myapps_data_${shape.name}_zip_',
      );
      addTearDown(() async {
        if (await output.exists()) await output.delete(recursive: true);
      });
      final transfer = ZipTransfer(
        storage: sandbox.storage,
        modules: sandbox.registry,
        archiveNamePrefix: shape.archivePrefix,
        clock: () => _fixedNow,
      );

      final zipPath = await transfer.exportZip(output.path);

      expect(zipPath, isNotNull);
      final entries = _zipEntries(File(zipPath!));
      final archiveName = p
          .basename(zipPath)
          .replaceAll(RegExp(r'\d{8}_\d{6}'), '<stamp>');
      await _expectGolden(
        shape,
        'zip_export_entries',
        '${entries.join('\n')}\narchiveName: $archiveName\n',
      );
    });
  });
}

/// Purpose: Register Phase 2 package golden tests for all app-shaped registries.
/// Inputs: None.
/// Returns: None.
/// Side effects: Registers Flutter tests.
/// Notes: The default mode verifies committed fixtures; GOLDEN_RECORD records.
void main() {
  for (final shape in _appShapes) {
    _registerShapeGoldens(shape);
  }
}
