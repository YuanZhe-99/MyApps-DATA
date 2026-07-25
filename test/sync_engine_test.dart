import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

import 'golden/fake_webdav_server.dart';
import 'golden/request_recorder.dart';

const _serverUrl = 'https://x.test/dav/files/u';
const _remotePath = '/MyApp';
const _remoteBase = '/dav/files/u/MyApp';
const _config = WebDAVConfig(
  serverUrl: _serverUrl,
  username: 'u',
  password: 'p',
  remotePath: _remotePath,
);
final _fixedNow = DateTime.utc(2026, 7, 24, 12);

class _TestStorage implements StorageAdapter {
  _TestStorage(this.directory);

  final Directory directory;
  Map<String, dynamic> config = {};

  @override
  Future<Directory> getAppDir() async => directory;

  @override
  Future<Map<String, dynamic>> readConfig() async => Map.of(config);

  @override
  Future<void> writeConfig(Map<String, dynamic> config) async {
    this.config = Map.of(config);
  }
}

DataModule _module({
  String fileName = 'data.json',
  String moduleId = 'data',
  ModuleMergeCallback? merge,
  ModulePostMergeTransform? postMergeTransform,
  ModulePreUploadTransform? preUploadTransform,
  ModuleImageReferences? referencedImages,
  bool indexMergedUploadProgress = true,
}) {
  return DataModule(
    fileName: fileName,
    moduleId: moduleId,
    validate: (raw) => jsonDecode(raw),
    merge:
        merge ??
        ({
          required String localJson,
          required String remoteJson,
          required String? baseJson,
          required bool autoResolve,
        }) => ModuleMergeOutcome(mergedJson: remoteJson),
    postMergeTransform: postMergeTransform,
    preUploadTransform: preUploadTransform,
    referencedImages: referencedImages,
    indexMergedUploadProgress: indexMergedUploadProgress,
  );
}

WebDavSyncEngine _engine({
  required Directory directory,
  required http.Client httpClient,
  required Iterable<DataModule> modules,
  bool failFastOnDownloadError = false,
}) {
  var nextId = 0;
  return WebDavSyncEngine(
    storage: _TestStorage(directory),
    modules: ModuleRegistry(modules),
    defaultRemotePath: _remotePath,
    failFastOnDownloadError: failFastOnDownloadError,
    clientFactory: (config) => WebDavClient(
      config,
      httpClient: httpClient,
      retryDelay: Duration.zero,
      heartbeatInterval: const Duration(days: 1),
    ),
    clock: () => _fixedNow,
    idGenerator: () => 'test-id-${++nextId}',
  );
}

File _localFile(Directory directory, String name) {
  return File(p.join(directory.path, name));
}

File _baseFile(Directory directory, String name) {
  return File(p.join(directory.path, '.sync_base', name));
}

http.StreamedResponse _response(int status, [String body = '']) {
  return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
}

void main() {
  late Directory directory;
  late FakeWebDAVServer server;
  late RequestRecorder recorder;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('myapps-data-engine-');
    server = FakeWebDAVServer();
    recorder = RequestRecorder(server);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  group('ModuleRegistry and merge contracts', () {
    test('preserves order and exposes both lookups', () {
      final first = _module(fileName: 'a.json', moduleId: 'a');
      final second = _module(fileName: 'b.json', moduleId: 'b');
      final registry = ModuleRegistry([first, second]);

      expect(registry.modules, [first, second]);
      expect(registry.byFileName['b.json'], same(second));
      expect(registry.byModuleId['a'], same(first));
      expect(() => registry.modules.add(first), throwsUnsupportedError);
    });

    test('rejects duplicate file names and module IDs', () {
      expect(
        () => ModuleRegistry([
          _module(fileName: 'same.json', moduleId: 'a'),
          _module(fileName: 'same.json', moduleId: 'b'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => ModuleRegistry([
          _module(fileName: 'a.json', moduleId: 'same'),
          _module(fileName: 'b.json', moduleId: 'same'),
        ]),
        throwsArgumentError,
      );
    });

    test(
      'pending outcome retains opaque state and resolves by namespaced key',
      () async {
        final state = Object();
        final outcome = ModuleMergeOutcome(
          conflicts: const [
            ModuleConflict(
              id: '1',
              resolutionKey: 'records:1',
              localRecord: 'local',
              remoteRecord: 'remote',
              displayName: 'Record 1',
            ),
          ],
          state: state,
          buildResolvedJson: (resolutions) =>
              jsonEncode({'value': resolutions['records:1']}),
        );

        expect(outcome.state, same(state));
        expect(outcome.conflicts.single.resolutionKey, 'records:1');
        expect(jsonDecode(await outcome.resolve({'records:1': 'chosen'})), {
          'value': 'chosen',
        });
      },
    );
  });

  group('config persistence', () {
    test('uses default path only when remotePath is missing', () async {
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: const [],
      );
      await _localFile(directory, 'webdav_config.json').writeAsString(
        jsonEncode({'serverUrl': 's', 'username': 'u', 'password': 'p'}),
      );
      expect((await engine.loadConfig())!.remotePath, _remotePath);

      await _localFile(directory, 'webdav_config.json').writeAsString(
        jsonEncode({
          'serverUrl': 's',
          'username': 'u',
          'password': 'p',
          'remotePath': '',
        }),
      );
      expect((await engine.loadConfig())!.remotePath, '');
    });

    test('save/load/delete round-trip keeps compact config shape', () async {
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: const [],
      );
      await engine.saveConfig(_config);
      final file = _localFile(directory, 'webdav_config.json');
      expect(await file.readAsString(), jsonEncode(_config.toJson()));
      expect((await engine.loadConfig())!.remotePath, _remotePath);
      await engine.deleteConfig();
      expect(await file.exists(), false);
    });
  });

  group('normal sync file state matrix', () {
    test(
      'local-only first sync uploads raw JSON and saves base after PUT',
      () async {
        var mergeCalls = 0;
        final module = _module(
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) {
                mergeCalls++;
                return ModuleMergeOutcome(mergedJson: remoteJson);
              },
        );
        const raw = '{"value":"local"}';
        await _localFile(directory, module.fileName).writeAsString(raw);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, true);
        expect(server.readText('$_remoteBase/data.json'), raw);
        expect(await _baseFile(directory, module.fileName).readAsString(), raw);
        expect(mergeCalls, 0);
        expect(engine.consumeLocalDataChanged(), false);
        expect(engine.progress.value.phase, SyncPhase.done);
        expect(server.exists('$_remoteBase/.lock'), false);
        expect(
          await _localFile(directory, '.sync_base/upload_lock.json').exists(),
          false,
        );
        final lockPut = recorder.exchanges.indexWhere(
          (e) => e.method == 'PUT' && e.path.endsWith('/.lock'),
        );
        final dataGet = recorder.exchanges.indexWhere(
          (e) => e.method == 'GET' && e.path.endsWith('/data.json'),
        );
        expect(lockPut, lessThan(dataGet));
      },
    );

    test(
      'remote-only sync copies raw JSON, saves base, and sets change flag',
      () async {
        const raw = '{"value":"remote"}';
        server.seed('$_remoteBase/data.json', raw);
        final module = _module();
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, true);
        expect(
          await _localFile(directory, module.fileName).readAsString(),
          raw,
        );
        expect(await _baseFile(directory, module.fileName).readAsString(), raw);
        expect(engine.consumeLocalDataChanged(), true);
        expect(engine.consumeLocalDataChanged(), false);
      },
    );

    test('both missing leaves a stale base untouched', () async {
      final module = _module();
      final base = _baseFile(directory, module.fileName);
      await base.parent.create(recursive: true);
      await base.writeAsString('stale');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [module],
      );

      expect((await engine.sync(_config)).success, true);
      expect(await base.readAsString(), 'stale');
      expect(await _localFile(directory, module.fileName).exists(), false);
    });

    test('raw-equal fast path skips merge/PUT and updates base', () async {
      var mergeCalls = 0;
      final module = _module(
        merge:
            ({
              required localJson,
              required remoteJson,
              required baseJson,
              required autoResolve,
            }) {
              mergeCalls++;
              return ModuleMergeOutcome(mergedJson: remoteJson);
            },
      );
      const raw = '{"same":true}';
      await _localFile(directory, module.fileName).writeAsString(raw);
      server.seed('$_remoteBase/data.json', raw);
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [module],
      );

      expect((await engine.sync(_config)).success, true);
      expect(mergeCalls, 0);
      expect(await _baseFile(directory, module.fileName).readAsString(), raw);
      expect(
        recorder.exchanges.where(
          (e) => e.method == 'PUT' && e.path.endsWith('/data.json'),
        ),
        isEmpty,
      );
    });

    test(
      'differing files run merge, transforms, local write, PUT, then base',
      () async {
        ModuleUploadContext? transformContext;
        final module = _module(
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) {
                expect(localJson, '{"value":"local"}');
                expect(remoteJson, '{"value":"remote"}');
                expect(baseJson, '{"value":"base"}');
                expect(autoResolve, false);
                return ModuleMergeOutcome(mergedJson: '{"value":"merged"}');
              },
          postMergeTransform: (raw) => raw.replaceFirst('merged', 'post'),
          preUploadTransform: (context) {
            transformContext = context;
            return context.nextJson.replaceFirst('post', 'final');
          },
        );
        await _localFile(
          directory,
          module.fileName,
        ).writeAsString('{"value":"local"}');
        final base = _baseFile(directory, module.fileName);
        await base.parent.create(recursive: true);
        await base.writeAsString('{"value":"base"}');
        server.seed('$_remoteBase/data.json', '{"value":"remote"}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        const expected = '{"value":"final"}';
        expect(result.success, true);
        expect(
          await _localFile(directory, module.fileName).readAsString(),
          expected,
        );
        expect(server.readText('$_remoteBase/data.json'), expected);
        expect(await base.readAsString(), expected);
        expect(transformContext!.reason, ModuleWriteReason.merge);
        expect(transformContext!.baseJson, '{"value":"base"}');
        expect(engine.consumeLocalDataChanged(), true);
        final dataPut = recorder.exchanges.singleWhere(
          (e) => e.method == 'PUT' && e.path.endsWith('/data.json'),
        );
        expect(dataPut.requestHeaders.containsKey('if-match'), false);
        expect(dataPut.requestHeaders.containsKey('if-none-match'), false);
      },
    );

    test(
      'module can preserve MyDay indeterminate merged-upload progress',
      () async {
        final module = _module(
          indexMergedUploadProgress: false,
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) => ModuleMergeOutcome(mergedJson: remoteJson),
        );
        await _localFile(
          directory,
          module.fileName,
        ).writeAsString('{"value":1}');
        server.seed('$_remoteBase/data.json', '{"value":2}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );
        final snapshots = <SyncProgress>[];
        engine.progress.addListener(() => snapshots.add(engine.progress.value));

        expect((await engine.sync(_config)).success, true);

        final upload = snapshots.singleWhere(
          (snapshot) => snapshot.phase == SyncPhase.uploadingData,
        );
        expect(upload.detail, module.fileName);
        expect(upload.current, 0);
        expect(upload.total, 0);
      },
    );

    test(
      'schema preservation composes base, local, and remote before upload',
      () async {
        const itemSchema = JsonPreservationSchema(knownKeys: {'id', 'name'});
        const schema = JsonPreservationSchema(
          knownKeys: {'value', 'records'},
          listFields: {
            'records': JsonListPreservation(
              keyField: 'id',
              itemSchema: itemSchema,
            ),
          },
        );
        final module = _module(
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) => ModuleMergeOutcome(
                mergedJson:
                    '{"value":"merged","records":[{"id":"1","name":"merged"}]}',
              ),
          preUploadTransform: (context) => JsonPreservation.preserveJsonString(
            nextJson: context.nextJson,
            sourceJsons: [
              context.baseJson,
              context.localJson,
              context.remoteJson,
            ],
            schema: schema,
          ),
        );
        const baseRaw =
            '{"value":"base","baseOnly":1,"shared":"base","records":[{"id":"1","name":"base","baseNested":1}]}';
        const localRaw =
            '{"value":"local","localOnly":2,"shared":"local","records":[{"id":"1","name":"local","localNested":2}]}';
        const remoteRaw =
            '{"value":"remote","remoteOnly":3,"shared":"remote","records":[{"id":"1","name":"remote","remoteNested":3}]}';
        await _localFile(directory, module.fileName).writeAsString(localRaw);
        final base = _baseFile(directory, module.fileName);
        await base.parent.create(recursive: true);
        await base.writeAsString(baseRaw);
        server.seed('$_remoteBase/data.json', remoteRaw);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        expect((await engine.sync(_config)).success, true);

        final written =
            jsonDecode(
                  await _localFile(directory, module.fileName).readAsString(),
                )
                as Map<String, dynamic>;
        expect(written['value'], 'merged');
        expect(written['baseOnly'], 1);
        expect(written['localOnly'], 2);
        expect(written['remoteOnly'], 3);
        expect(written['shared'], 'remote');
        final record = (written['records'] as List).single as Map;
        expect(record['name'], 'merged');
        expect(record['baseNested'], 1);
        expect(record['localNested'], 2);
        expect(record['remoteNested'], 3);
        expect(jsonDecode(server.readText('$_remoteBase/data.json')!), written);
        expect(jsonDecode(await base.readAsString()), written);
      },
    );

    test('one concurrent local edit causes exactly one re-merge', () async {
      var mergeCalls = 0;
      late File localFile;
      final module = _module(
        merge:
            ({
              required localJson,
              required remoteJson,
              required baseJson,
              required autoResolve,
            }) async {
              mergeCalls++;
              if (mergeCalls == 1) {
                await localFile.writeAsString('{"value":"latest"}');
              }
              return ModuleMergeOutcome(mergedJson: localJson);
            },
      );
      localFile = _localFile(directory, module.fileName);
      await localFile.writeAsString('{"value":"initial"}');
      server.seed('$_remoteBase/data.json', '{"value":"remote"}');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [module],
      );

      expect((await engine.sync(_config)).success, true);
      expect(mergeCalls, 2);
      expect(await localFile.readAsString(), '{"value":"latest"}');
      expect(server.readText('$_remoteBase/data.json'), '{"value":"latest"}');
    });

    test(
      'upload failure leaves merged local data but keeps old base',
      () async {
        final module = _module(
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) => ModuleMergeOutcome(mergedJson: '{"value":"merged"}'),
        );
        await _localFile(
          directory,
          module.fileName,
        ).writeAsString('{"value":"local"}');
        final base = _baseFile(directory, module.fileName);
        await base.parent.create(recursive: true);
        await base.writeAsString('{"value":"base"}');
        server.seed('$_remoteBase/data.json', '{"value":"remote"}');
        server.injectFault(
          (method, path) => method == 'PUT' && path.endsWith('/data.json'),
          Faults.serverError(),
        );
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, false);
        expect(
          result.error,
          contains('data.json: force-upload failed: HTTP 500'),
        );
        expect(
          await _localFile(directory, module.fileName).readAsString(),
          '{"value":"merged"}',
        );
        expect(await base.readAsString(), '{"value":"base"}');
        expect(engine.consumeLocalDataChanged(), true);
      },
    );
  });

  group('errors, pending conflicts, and finalization', () {
    test('download errors continue to later modules by default', () async {
      final first = _module(fileName: 'first.json', moduleId: 'first');
      final second = _module(fileName: 'second.json', moduleId: 'second');
      server.injectFault(
        (method, path) => method == 'GET' && path.endsWith('/first.json'),
        () => _response(403, 'Forbidden'),
      );
      server.seed('$_remoteBase/second.json', '{"second":true}');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [first, second],
      );

      final result = await engine.sync(_config);

      expect(result.success, false);
      expect(result.error, 'first.json: download failed: HTTP 403');
      expect(await _localFile(directory, second.fileName).exists(), true);
    });

    test('fail-fast download policy skips later modules', () async {
      final first = _module(fileName: 'first.json', moduleId: 'first');
      final second = _module(fileName: 'second.json', moduleId: 'second');
      server.injectFault(
        (method, path) => method == 'GET' && path.endsWith('/first.json'),
        () => _response(403, 'Forbidden'),
      );
      server.seed('$_remoteBase/second.json', '{"second":true}');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [first, second],
        failFastOnDownloadError: true,
      );

      final result = await engine.sync(_config);

      expect(result.success, false);
      expect(await _localFile(directory, second.fileName).exists(), false);
      expect(
        recorder.exchanges.where((e) => e.path.endsWith('/second.json')),
        isEmpty,
      );
    });

    test(
      'conflict remains pending; finalize rebuilds, rereads, uploads, bases',
      () async {
        final typedState = Object();
        ModuleUploadContext? finalizeContext;
        final module = _module(
          merge:
              ({
                required localJson,
                required remoteJson,
                required baseJson,
                required autoResolve,
              }) => ModuleMergeOutcome(
                conflicts: const [
                  ModuleConflict(
                    id: '1',
                    resolutionKey: 'record:1',
                    localRecord: 'local',
                    remoteRecord: 'remote',
                    displayName: 'Record',
                  ),
                ],
                state: typedState,
                buildResolvedJson: (resolutions) =>
                    jsonEncode({'value': resolutions['record:1'] ?? 'local'}),
              ),
          postMergeTransform: (raw) => raw.replaceFirst('chosen', 'post'),
          preUploadTransform: (context) {
            if (context.reason == ModuleWriteReason.finalize) {
              finalizeContext = context;
            }
            return context.nextJson;
          },
        );
        final local = _localFile(directory, module.fileName);
        await local.writeAsString('{"value":"local"}');
        final base = _baseFile(directory, module.fileName);
        await base.parent.create(recursive: true);
        await base.writeAsString('{"value":"base"}');
        server.seed('$_remoteBase/data.json', '{"value":"remote"}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final firstResult = await engine.sync(_config);

        expect(firstResult.success, true);
        expect(firstResult.hasConflicts, true);
        expect(firstResult.pending!.allConflicts.single.id, '1');
        expect(
          firstResult.pending!.forModuleId('data')!.state,
          same(typedState),
        );
        expect(await local.readAsString(), '{"value":"local"}');
        expect(server.readText('$_remoteBase/data.json'), '{"value":"remote"}');
        expect(await base.readAsString(), '{"value":"base"}');

        recorder.reset();
        final finalized = await engine.finalizePendingSync(
          _config,
          firstResult.pending!,
          {
            'data': {'record:1': 'chosen'},
          },
        );

        expect(finalized, true);
        expect(await local.readAsString(), '{"value":"post"}');
        expect(server.readText('$_remoteBase/data.json'), '{"value":"post"}');
        expect(await base.readAsString(), '{"value":"post"}');
        expect(finalizeContext!.reason, ModuleWriteReason.finalize);
        expect(finalizeContext!.baseJson, isNull);
        expect(finalizeContext!.localJson, '{"value":"local"}');
        expect(finalizeContext!.remoteJson, '{"value":"remote"}');
        expect(engine.consumeLocalDataChanged(), true);
        expect(server.exists('$_remoteBase/.lock'), false);
        final remoteRead = recorder.exchanges.indexWhere(
          (e) => e.method == 'GET' && e.path.endsWith('/data.json'),
        );
        final dataPut = recorder.exchanges.indexWhere(
          (e) => e.method == 'PUT' && e.path.endsWith('/data.json'),
        );
        expect(remoteRead, lessThan(dataPut));
      },
    );

    test('pending conflicts can coexist with another module error', () async {
      final conflict = _module(
        fileName: 'conflict.json',
        moduleId: 'conflict',
        merge:
            ({
              required localJson,
              required remoteJson,
              required baseJson,
              required autoResolve,
            }) => ModuleMergeOutcome(
              conflicts: const [
                ModuleConflict(
                  id: '1',
                  localRecord: 'l',
                  remoteRecord: 'r',
                  displayName: '1',
                ),
              ],
              buildResolvedJson: (_) => '{}',
            ),
      );
      final broken = _module(fileName: 'broken.json', moduleId: 'broken');
      await _localFile(directory, conflict.fileName).writeAsString('{"v":"l"}');
      server.seed('$_remoteBase/conflict.json', '{"v":"r"}');
      server.injectFault(
        (method, path) => method == 'GET' && path.endsWith('/broken.json'),
        () => _response(403),
      );
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [conflict, broken],
      );

      final result = await engine.sync(_config);

      expect(result.success, false);
      expect(result.hasConflicts, true);
      expect(result.error, 'broken.json: download failed: HTTP 403');
    });

    test(
      'finalize aborts an unreadable remote module and releases its lock',
      () async {
        final module = _module();
        final local = _localFile(directory, module.fileName);
        await local.writeAsString('{"value":"local"}');
        final outcome = ModuleMergeOutcome(
          conflicts: const [
            ModuleConflict(
              id: '1',
              localRecord: 'local',
              remoteRecord: 'remote',
              displayName: 'Record',
            ),
          ],
          buildResolvedJson: (_) => '{"value":"resolved"}',
        );
        final pending = EnginePendingSync([
          EnginePendingModule(module: module, outcome: outcome),
        ]);
        server.injectFault(
          (method, path) => method == 'GET' && path.endsWith('/data.json'),
          () => _response(403),
        );
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.finalizePendingSync(
          _config,
          pending,
          const {},
        );

        expect(result, false);
        expect(await local.readAsString(), '{"value":"local"}');
        expect(server.exists('$_remoteBase/.lock'), false);
        expect(engine.consumeLocalDataChanged(), false);
      },
    );

    test('active foreign lock blocks before data download', () async {
      server.seed(
        '$_remoteBase/.lock',
        jsonEncode({
          'clientId': 'other',
          'token': 'token',
          'startedAt': _fixedNow.toIso8601String(),
          'updatedAt': _fixedNow.toIso8601String(),
          'ttlSeconds': 60,
        }),
      );
      final module = _module();
      await _localFile(directory, module.fileName).writeAsString('{}');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [module],
      );

      final result = await engine.sync(_config);

      expect(result.success, false);
      expect(
        result.error,
        'Another device is uploading; retry after the lock expires.',
      );
      expect(
        recorder.exchanges.where((e) => e.path.endsWith('/data.json')),
        isEmpty,
      );
    });

    test('expired foreign lock is replaced and released', () async {
      server.seed(
        '$_remoteBase/.lock',
        jsonEncode({
          'clientId': 'other',
          'token': 'token',
          'startedAt': _fixedNow
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
          'updatedAt': _fixedNow
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
          'ttlSeconds': 60,
        }),
      );
      final module = _module();
      await _localFile(directory, module.fileName).writeAsString('{}');
      final engine = _engine(
        directory: directory,
        httpClient: recorder,
        modules: [module],
      );

      expect((await engine.sync(_config)).success, true);
      expect(server.exists('$_remoteBase/.lock'), false);
      expect(server.readText('$_remoteBase/data.json'), '{}');
    });

    test(
      'matching interrupted lock resumes its existing upload token',
      () async {
        const clientId = 'stable-client';
        const token = 'resume-token';
        final lockJson = jsonEncode({
          'clientId': clientId,
          'token': token,
          'startedAt': _fixedNow.toIso8601String(),
          'updatedAt': _fixedNow.toIso8601String(),
          'ttlSeconds': 60,
        });
        final baseDir = Directory(p.join(directory.path, '.sync_base'));
        await baseDir.create(recursive: true);
        await File(
          p.join(baseDir.path, 'client_id.txt'),
        ).writeAsString(clientId);
        await File(
          p.join(baseDir.path, 'upload_lock.json'),
        ).writeAsString(lockJson);
        server.seed('$_remoteBase/.lock', lockJson);
        server.seed('$_remoteBase/data.json', '{}');
        final module = _module();
        await _localFile(directory, module.fileName).writeAsString('{}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        expect((await engine.sync(_config)).success, true);

        final lockPuts = recorder.exchanges.where(
          (exchange) =>
              exchange.method == 'PUT' && exchange.path.endsWith('/.lock'),
        );
        expect(lockPuts, isNotEmpty);
        expect(
          lockPuts.every(
            (exchange) =>
                (jsonDecode(utf8.decode(exchange.body)) as Map)['token'] ==
                token,
          ),
          true,
        );
        expect(
          await File(p.join(baseDir.path, 'upload_lock.json')).exists(),
          false,
        );
        expect(server.exists('$_remoteBase/.lock'), false);
      },
    );

    test(
      'HTTP 412 during lock acquisition uses fixed contention message',
      () async {
        final module = _module();
        await _localFile(directory, module.fileName).writeAsString('{}');
        server.injectFault(
          (method, path) => method == 'PUT' && path.endsWith('/.lock'),
          () => _response(412, 'Precondition Failed'),
        );
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, false);
        expect(
          result.error,
          'Another device started uploading; retry after the lock expires.',
        );
        expect(
          recorder.exchanges.where((e) => e.path.endsWith('/data.json')),
          isEmpty,
        );
        expect(
          await _localFile(directory, '.sync_base/upload_lock.json').exists(),
          false,
        );
      },
    );
  });

  group('referenced image sync', () {
    Set<String> references(String raw) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (json['images'] as List<dynamic>).cast<String>().toSet();
    }

    test(
      'uploads and downloads missing referenced images additively',
      () async {
        final module = _module(referencedImages: references);
        const raw = '{"images":["local.png","remote.png"]}';
        await _localFile(directory, module.fileName).writeAsString(raw);
        server.seed('$_remoteBase/data.json', raw);
        final imageDir = Directory(p.join(directory.path, 'images'));
        await imageDir.create();
        await File(p.join(imageDir.path, 'local.png')).writeAsBytes([1, 2]);
        server.seed('$_remoteBase/images/remote.png', [3, 4]);
        server.seed('$_remoteBase/images/orphan.png', [9]);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, true);
        expect(result.warnings, isEmpty);
        expect(server.files['$_remoteBase/images/local.png']!.bytes, [1, 2]);
        expect(await File(p.join(imageDir.path, 'remote.png')).readAsBytes(), [
          3,
          4,
        ]);
        expect(await File(p.join(imageDir.path, 'orphan.png')).exists(), false);
        expect(engine.consumeLocalDataChanged(), true);
      },
    );

    test(
      'listing failure skips normal image transfer with fixed warning',
      () async {
        final module = _module(referencedImages: references);
        const raw = '{"images":["local.png"]}';
        await _localFile(directory, module.fileName).writeAsString(raw);
        server.seed('$_remoteBase/data.json', raw);
        final imageDir = Directory(p.join(directory.path, 'images'));
        await imageDir.create();
        await File(p.join(imageDir.path, 'local.png')).writeAsBytes([1]);
        server.injectFault(
          (method, path) => method == 'PROPFIND' && path.endsWith('/images/'),
          Faults.serverError(),
        );
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, true);
        expect(result.warnings, const [
          'Image sync skipped: could not list the remote images directory',
        ]);
        expect(server.exists('$_remoteBase/images/local.png'), false);
      },
    );

    test(
      'empty MKCOL collection lists successfully and accepts first image',
      () async {
        final module = _module(referencedImages: references);
        const raw = '{"images":["first.png"]}';
        await _localFile(directory, module.fileName).writeAsString(raw);
        server.seed('$_remoteBase/data.json', raw);
        final imageDir = Directory(p.join(directory.path, 'images'));
        await imageDir.create();
        await File(p.join(imageDir.path, 'first.png')).writeAsBytes([7]);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.sync(_config);

        expect(result.success, true);
        expect(result.warnings, isEmpty);
        expect(server.files['$_remoteBase/images/first.png']!.bytes, [7]);
      },
    );

    test(
      'downloads images in referenced-set order, not listing order',
      () async {
        final module = _module(referencedImages: references);
        const raw = '{"images":["second.png","first.png"]}';
        await _localFile(directory, module.fileName).writeAsString(raw);
        server.seed('$_remoteBase/data.json', raw);
        server.seed('$_remoteBase/images/first.png', [1]);
        server.seed('$_remoteBase/images/second.png', [2]);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        expect((await engine.sync(_config)).success, true);

        final imageGets = recorder.exchanges
            .where(
              (exchange) =>
                  exchange.method == 'GET' &&
                  exchange.path.contains('/images/'),
            )
            .map((exchange) => p.basename(exchange.path))
            .toList();
        expect(imageGets, ['second.png', 'first.png']);
      },
    );
  });

  group('force operations', () {
    test(
      'forceUpload sends raw local modules without data GET and saves bases',
      () async {
        final first = _module(fileName: 'first.json', moduleId: 'first');
        final second = _module(fileName: 'second.json', moduleId: 'second');
        await _localFile(directory, first.fileName).writeAsString('{"a":1}');
        await _localFile(directory, second.fileName).writeAsString('{"b":2}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [first, second],
        );

        final result = await engine.forceUpload(_config);

        expect(result.success, true);
        expect(server.readText('$_remoteBase/first.json'), '{"a":1}');
        expect(server.readText('$_remoteBase/second.json'), '{"b":2}');
        expect(
          await _baseFile(directory, first.fileName).readAsString(),
          '{"a":1}',
        );
        expect(
          recorder.exchanges.where(
            (e) =>
                e.method == 'GET' &&
                (e.path.endsWith('/first.json') ||
                    e.path.endsWith('/second.json')),
          ),
          isEmpty,
        );
        expect(engine.consumeLocalDataChanged(), false);
      },
    );

    test(
      'forceUpload skips a missing local module and keeps remote/base',
      () async {
        final module = _module();
        server.seed('$_remoteBase/data.json', '{"remote":true}');
        final base = _baseFile(directory, module.fileName);
        await base.parent.create(recursive: true);
        await base.writeAsString('old-base');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        expect((await engine.forceUpload(_config)).success, true);
        expect(server.readText('$_remoteBase/data.json'), '{"remote":true}');
        expect(await base.readAsString(), 'old-base');
      },
    );

    test(
      'forceDownload is lock-free, keeps missing local, and syntax-checks',
      () async {
        final present = _module(fileName: 'present.json', moduleId: 'present');
        final missing = _module(fileName: 'missing.json', moduleId: 'missing');
        server.seed('$_remoteBase/present.json', '[]');
        await _localFile(
          directory,
          missing.fileName,
        ).writeAsString('{"keep":true}');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [present, missing],
        );

        final result = await engine.forceDownload(_config);

        expect(result.success, true);
        expect(
          await _localFile(directory, present.fileName).readAsString(),
          '[]',
        );
        expect(
          await _localFile(directory, missing.fileName).readAsString(),
          '{"keep":true}',
        );
        expect(result.warnings, [
          'missing.json: not found on remote; local file kept',
        ]);
        expect(
          recorder.exchanges.where(
            (e) => e.path.endsWith('/.lock') || e.method == 'MKCOL',
          ),
          isEmpty,
        );
        expect(engine.consumeLocalDataChanged(), true);
      },
    );

    test(
      'forceUpload falls back to uploading images when listing fails',
      () async {
        final module = _module(
          referencedImages: (raw) =>
              (jsonDecode(raw)['images'] as List<dynamic>)
                  .cast<String>()
                  .toSet(),
        );
        await _localFile(
          directory,
          module.fileName,
        ).writeAsString('{"images":["cover.png"]}');
        final imageDir = Directory(p.join(directory.path, 'images'));
        await imageDir.create();
        await File(p.join(imageDir.path, 'cover.png')).writeAsBytes([1, 2, 3]);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.forceUpload(_config);

        expect(result.success, true);
        expect(result.warnings, isEmpty);
        expect(server.files['$_remoteBase/images/cover.png']!.bytes, [1, 2, 3]);
      },
    );

    test(
      'forceDownload downloads referenced remote images additively',
      () async {
        final module = _module(
          referencedImages: (raw) =>
              (jsonDecode(raw)['images'] as List<dynamic>)
                  .cast<String>()
                  .toSet(),
        );
        server.seed('$_remoteBase/data.json', '{"images":["cover.png"]}');
        server.seed('$_remoteBase/images/cover.png', [4, 5]);
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.forceDownload(_config);

        expect(result.success, true);
        expect(result.warnings, isEmpty);
        expect(
          await File(
            p.join(directory.path, 'images', 'cover.png'),
          ).readAsBytes(),
          [4, 5],
        );
      },
    );

    test(
      'forceDownload rejects invalid JSON without changing that local file',
      () async {
        final module = _module();
        await _localFile(
          directory,
          module.fileName,
        ).writeAsString('{"old":true}');
        server.seed('$_remoteBase/data.json', 'not-json');
        final engine = _engine(
          directory: directory,
          httpClient: recorder,
          modules: [module],
        );

        final result = await engine.forceDownload(_config);

        expect(result.success, false);
        expect(result.error, 'data.json: remote content is not valid JSON');
        expect(
          await _localFile(directory, module.fileName).readAsString(),
          '{"old":true}',
        );
      },
    );
  });

  test('shared operation guard rejects overlapping sync/force calls', () async {
    final mergeStarted = Completer<void>();
    final unblockMerge = Completer<void>();
    final module = _module(
      merge:
          ({
            required localJson,
            required remoteJson,
            required baseJson,
            required autoResolve,
          }) async {
            mergeStarted.complete();
            await unblockMerge.future;
            return ModuleMergeOutcome(mergedJson: remoteJson);
          },
    );
    await _localFile(directory, module.fileName).writeAsString('{"v":"local"}');
    server.seed('$_remoteBase/data.json', '{"v":"remote"}');
    final engine = _engine(
      directory: directory,
      httpClient: recorder,
      modules: [module],
    );

    final running = engine.sync(_config);
    await mergeStarted.future;
    final rejected = await engine.forceUpload(_config);
    expect(rejected.success, false);
    expect(rejected.error, 'Sync already in progress');
    expect(engine.progress.value.phase, SyncPhase.merging);
    unblockMerge.complete();
    expect((await running).success, true);
  });
}
