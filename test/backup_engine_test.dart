import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

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

class _MutableClock {
  DateTime now = DateTime(2026, 7, 24, 12);

  DateTime call() => now;
}

DataModule _module(
  String fileName,
  String moduleId, {
  ModuleValidator? validate,
}) {
  return DataModule(
    fileName: fileName,
    moduleId: moduleId,
    validate: validate ?? (raw) => jsonDecode(raw),
    merge:
        ({
          required String localJson,
          required String remoteJson,
          required String? baseJson,
          required bool autoResolve,
        }) => ModuleMergeOutcome(mergedJson: remoteJson),
  );
}

void main() {
  late Directory directory;
  late _TestStorage storage;
  late _MutableClock clock;

  BackupEngine engine({bool syntheticImagesModule = false}) {
    return BackupEngine(
      storage: storage,
      modules: ModuleRegistry([
        _module('a_data.json', 'a'),
        _module('b_data.json', 'b'),
      ]),
      defaultRemotePath: '/MyApp',
      syntheticImagesModule: syntheticImagesModule,
      clock: clock.call,
    );
  }

  Directory backupDir() => Directory(p.join(directory.path, 'backups'));
  Directory blobDir() => Directory(p.join(directory.path, 'backups', 'blobs'));

  List<File> bundles() {
    final dir = backupDir();
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('backup_'))
        .toList();
  }

  List<File> blobs() {
    final dir = blobDir();
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().toList();
  }

  Future<void> writeData(String name, Object json) async {
    await File(p.join(directory.path, name)).writeAsString(jsonEncode(json));
  }

  Future<void> writeImage(String name, List<int> bytes) async {
    final file = File(p.join(directory.path, 'images', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<void> ageBlobs(Duration age) async {
    for (final blob in blobs()) {
      await blob.setLastModified(clock.now.subtract(age));
    }
  }

  Future<void> writeWebDavConfig({bool autoSync = true}) async {
    await File(p.join(directory.path, 'webdav_config.json')).writeAsString(
      jsonEncode(
        WebDAVConfig(
          serverUrl: 'https://x.test',
          username: 'u',
          password: 'p',
          remotePath: '/MyApp',
          autoSync: autoSync,
        ).toJson(),
      ),
    );
  }

  bool readAutoSync() {
    final raw = File(
      p.join(directory.path, 'webdav_config.json'),
    ).readAsStringSync();
    return (jsonDecode(raw) as Map<String, dynamic>)['autoSync'] as bool;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup_engine_test');
    storage = _TestStorage(directory);
    clock = _MutableClock();
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  group('createBackup', () {
    test(
      'writes v2 bundle with module strings and no createdAt/modules',
      () async {
        await writeData('a_data.json', {'items': 1});
        await writeData('b_data.json', {'items': 2});

        final file = await engine().createBackup();

        expect(file, isNotNull);
        final bundle =
            jsonDecode(await file!.readAsString()) as Map<String, dynamic>;
        expect(bundle['_backupFormat'], BackupEngine.formatVersion);
        expect(bundle.containsKey('createdAt'), isFalse);
        expect(bundle.containsKey('modules'), isFalse);
        expect(bundle['a_data.json'], jsonEncode({'items': 1}));
        expect(bundle['b_data.json'], jsonEncode({'items': 2}));
        expect(bundle.containsKey('_imageRefs'), isFalse);
        expect(p.basename(file.path), 'backup_20260724_120000.json');
      },
    );

    test('skips module files that do not exist', () async {
      await writeData('a_data.json', {'items': 1});

      final file = await engine().createBackup();

      final bundle =
          jsonDecode(await file!.readAsString()) as Map<String, dynamic>;
      expect(bundle.containsKey('a_data.json'), isTrue);
      expect(bundle.containsKey('b_data.json'), isFalse);
    });

    test('deduplicates identical images into one shared blob', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));

      await engine().createBackup();
      clock.now = clock.now.add(const Duration(seconds: 1));
      await engine().createBackup();

      expect(bundles(), hasLength(2));
      expect(blobs(), hasLength(1));
      expect(
        p.basename(blobs().single.path),
        '${sha256.convert(utf8.encode('image-bytes'))}.png',
      );
      for (final bundle in bundles()) {
        final decoded =
            jsonDecode(await bundle.readAsString()) as Map<String, dynamic>;
        expect(decoded['_imageRefs'], {
          'images/cover.png': p.basename(blobs().single.path),
        });
      }
    });

    test('changed image content creates a second blob', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('one'));
      await engine().createBackup();

      clock.now = clock.now.add(const Duration(seconds: 1));
      await writeImage('cover.png', utf8.encode('two'));
      await engine().createBackup();

      expect(blobs(), hasLength(2));
    });

    test(
      'creates a bundle with only _backupFormat when no data exists',
      () async {
        final file = await engine().createBackup();

        final bundle =
            jsonDecode(await file!.readAsString()) as Map<String, dynamic>;
        expect(bundle.keys, ['_backupFormat']);
      },
    );
  });

  group('blob GC', () {
    test('keeps blob referenced by a remaining backup', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final first = (await engine().createBackup())!;
      clock.now = clock.now.add(const Duration(seconds: 1));
      await engine().createBackup();
      await ageBlobs(const Duration(hours: 1));

      await engine().deleteBackup(first);

      expect(blobs(), hasLength(1));
    });

    test('collects blob once no backup references it', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final first = (await engine().createBackup())!;
      clock.now = clock.now.add(const Duration(seconds: 1));
      final second = (await engine().createBackup())!;
      await ageBlobs(const Duration(hours: 1));

      await engine().deleteBackup(first);
      await engine().deleteBackup(second);

      expect(blobs(), isEmpty);
    });

    test('aborts the whole pass when any bundle is unparseable', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final good = (await engine().createBackup())!;
      final corrupt = File(
        p.join(backupDir().path, 'backup_20260724_120100.json'),
      );
      await corrupt.writeAsString('{not json');
      await ageBlobs(const Duration(hours: 1));

      await engine().deleteBackup(good);

      expect(blobs(), hasLength(1));
    });

    test('never collects blobs younger than the grace window', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final backup = (await engine().createBackup())!;
      await ageBlobs(const Duration(minutes: 5));

      await engine().deleteBackup(backup);

      expect(blobs(), hasLength(1));
    });
  });

  group('retention', () {
    test('deletes bundles older than retentionDays', () async {
      await writeData('a_data.json', {'items': 1});
      final old = (await engine().createBackup())!;

      clock.now = clock.now.add(const Duration(days: 10));
      final instance = engine()..retentionDays = 7;
      final fresh = (await instance.createBackup())!;

      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    });

    test('retentionDays 0 keeps backups forever', () async {
      await writeData('a_data.json', {'items': 1});
      final old = (await engine().createBackup())!;

      clock.now = clock.now.add(const Duration(days: 3650));
      await engine().createBackup();

      expect(await old.exists(), isTrue);
    });
  });

  group('listBackups', () {
    test('sorts newest first and flags corrupt bundles', () async {
      await writeData('a_data.json', {'items': 1});
      await engine().createBackup();
      clock.now = clock.now.add(const Duration(seconds: 1));
      await engine().createBackup();
      final corrupt = File(
        p.join(backupDir().path, 'backup_20260724_115900.json'),
      );
      await corrupt.writeAsString('{not json');

      final list = await engine().listBackups();

      expect(list, hasLength(3));
      expect(list.first.date.isAfter(list[1].date), isTrue);
      expect(list.where((b) => b.corrupt), hasLength(1));
      expect(list.first.corrupt, isFalse);
    });

    test('adds referenced blob sizes to the displayed size', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final file = (await engine().createBackup())!;

      final list = await engine().listBackups();

      expect(list, hasLength(1));
      expect(
        list.single.sizeBytes,
        await file.length() + utf8.encode('image-bytes').length,
      );
    });

    test('falls back to mtime when the filename stamp is malformed', () async {
      final weird = File(p.join(backupDir().path, 'backup_not-a-date.json'));
      await weird.parent.create(recursive: true);
      await weird.writeAsString(jsonEncode({'_backupFormat': 2}));

      final list = await engine().listBackups();

      expect(list, hasLength(1));
      expect(list.single.date, (await weird.stat()).modified);
    });
  });

  group('getBackupModules', () {
    test('returns present module ids in registry order', () async {
      await writeData('b_data.json', {'items': 2});
      await writeData('a_data.json', {'items': 1});
      final file = (await engine().createBackup())!;

      expect(await engine().getBackupModules(file), ['a', 'b']);
    });

    test('appends synthetic images module only when enabled', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final file = (await engine().createBackup())!;

      expect(await engine().getBackupModules(file), ['a']);
      expect(await engine(syntheticImagesModule: true).getBackupModules(file), [
        'a',
        'images',
      ]);
    });

    test('returns empty list for unparseable bundles', () async {
      final file = File(p.join(directory.path, 'broken.json'));
      await file.writeAsString('{not json');

      expect(await engine().getBackupModules(file), isEmpty);
    });
  });

  group('restoreBackup', () {
    Future<File> makeBundle(Map<String, dynamic> bundle) async {
      final file = File(p.join(directory.path, 'restore_source.json'));
      await file.writeAsString(jsonEncode(bundle));
      return file;
    }

    test('restores module files and v2 blob images', () async {
      await writeData('a_data.json', {'items': 1});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final backup = (await engine().createBackup())!;
      await File(p.join(directory.path, 'a_data.json')).delete();
      await File(p.join(directory.path, 'images', 'cover.png')).delete();

      final result = await engine().restoreBackup(backup);

      expect(result.ok, isTrue);
      expect(result.wroteAnything, isTrue);
      expect(result.missingImages, 0);
      expect(
        jsonDecode(
          await File(p.join(directory.path, 'a_data.json')).readAsString(),
        ),
        {'items': 1},
      );
      expect(
        await File(p.join(directory.path, 'images', 'cover.png')).readAsBytes(),
        utf8.encode('image-bytes'),
      );
    });

    test('validation failure aborts before writing anything', () async {
      await writeData('a_data.json', {'original': true});
      final validating = BackupEngine(
        storage: storage,
        modules: ModuleRegistry([
          _module('a_data.json', 'a'),
          _module(
            'b_data.json',
            'b',
            validate: (raw) =>
                throw DataFileValidationException('b_data.json', 'bad'),
          ),
        ]),
        defaultRemotePath: '/MyApp',
        clock: clock.call,
      );
      final bundle = await makeBundle({
        '_backupFormat': 2,
        'a_data.json': jsonEncode({'items': 1}),
        'b_data.json': jsonEncode({'items': 2}),
      });

      final result = await validating.restoreBackup(bundle);

      expect(result.ok, isFalse);
      expect(result.wroteAnything, isFalse);
      expect(
        jsonDecode(
          await File(p.join(directory.path, 'a_data.json')).readAsString(),
        ),
        {'original': true},
      );
      expect(
        await File(p.join(directory.path, 'b_data.json')).exists(),
        isFalse,
      );
    });

    test('restores only the selected modules', () async {
      await writeData('a_data.json', {'items': 1});
      await writeData('b_data.json', {'items': 2});
      final backup = (await engine().createBackup())!;
      await File(p.join(directory.path, 'a_data.json')).delete();
      await File(p.join(directory.path, 'b_data.json')).delete();

      final result = await engine().restoreBackup(backup, moduleKeys: {'b'});

      expect(result.ok, isTrue);
      expect(
        await File(p.join(directory.path, 'a_data.json')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(directory.path, 'b_data.json')).exists(),
        isTrue,
      );
    });

    test('counts missing blobs without failing the restore', () async {
      final bundle = await makeBundle({
        '_backupFormat': 2,
        'a_data.json': jsonEncode({'items': 1}),
        '_imageRefs': {'images/gone.png': '${'0' * 64}.png'},
      });

      final result = await engine().restoreBackup(bundle);

      expect(result.ok, isTrue);
      expect(result.missingImages, 1);
      expect(
        await File(p.join(directory.path, 'images', 'gone.png')).exists(),
        isFalse,
      );
    });

    test(
      'restores legacy v1 inline base64 images with tolerant keys',
      () async {
        final bundle = await makeBundle({
          'a_data.json': jsonEncode({'items': 1}),
          '_images': {
            'images/prefixed.png': base64Encode(utf8.encode('one')),
            'bare.png': base64Encode(utf8.encode('two')),
          },
        });

        final result = await engine().restoreBackup(bundle);

        expect(result.ok, isTrue);
        expect(
          await File(
            p.join(directory.path, 'images', 'prefixed.png'),
          ).readAsBytes(),
          utf8.encode('one'),
        );
        expect(
          await File(
            p.join(directory.path, 'images', 'bare.png'),
          ).readAsBytes(),
          utf8.encode('two'),
        );
      },
    );

    test('rejects traversal, nested, and absolute image keys', () async {
      final payload = base64Encode(utf8.encode('x'));
      final bundle = await makeBundle({
        '_images': {
          '..\\escape.txt': payload,
          'images/../collapsed.png': payload,
          'nested/inner.png': payload,
          '/abs/x.png': payload,
          'C:\\abs\\y.png': payload,
        },
      });

      final result = await engine().restoreBackup(bundle);

      expect(result.ok, isTrue);
      expect(
        await File(p.join(directory.path, 'escape.txt')).exists(),
        isFalse,
      );
      final imagesDir = Directory(p.join(directory.path, 'images'));
      final written = (await imagesDir.exists())
          ? await imagesDir.list().map((e) => p.basename(e.path)).toList()
          : <String>[];
      // `images/../collapsed.png` normalizes to a bare basename before
      // sanitization, matching MyDevice's tolerant `_safeImageBasename`;
      // every other crafted key is rejected.
      expect(written, ['collapsed.png']);
    });

    test('corrupt bundle fails without writing anything', () async {
      await writeData('a_data.json', {'original': true});
      final file = File(p.join(directory.path, 'broken.json'));
      await file.writeAsString('{not json');

      final result = await engine().restoreBackup(file);

      expect(result.ok, isFalse);
      expect(result.wroteAnything, isFalse);
      expect(
        jsonDecode(
          await File(p.join(directory.path, 'a_data.json')).readAsString(),
        ),
        {'original': true},
      );
    });

    test('non-string module payload fails without writing anything', () async {
      final bundle = await makeBundle({'_backupFormat': 2, 'a_data.json': 42});

      final result = await engine().restoreBackup(bundle);

      expect(result.ok, isFalse);
      expect(result.wroteAnything, isFalse);
    });

    group('synthetic images module', () {
      test('gates image restore on the images module selection', () async {
        await writeData('a_data.json', {'items': 1});
        await writeImage('cover.png', utf8.encode('image-bytes'));
        final backup = (await engine(
          syntheticImagesModule: true,
        ).createBackup())!;
        await File(p.join(directory.path, 'images', 'cover.png')).delete();

        final withoutImages = await engine(
          syntheticImagesModule: true,
        ).restoreBackup(backup, moduleKeys: {'a'});
        expect(withoutImages.ok, isTrue);
        expect(
          await File(p.join(directory.path, 'images', 'cover.png')).exists(),
          isFalse,
        );

        final withImages = await engine(
          syntheticImagesModule: true,
        ).restoreBackup(backup, moduleKeys: {'images'});
        expect(withImages.ok, isTrue);
        expect(
          await File(p.join(directory.path, 'images', 'cover.png')).exists(),
          isTrue,
        );
        expect(
          await File(p.join(directory.path, 'a_data.json')).readAsString(),
          jsonEncode({'items': 1}),
        );
      });
    });

    group('I5 auto-sync interplay', () {
      test(
        'disables autoSync before writing and keeps it off on success',
        () async {
          await writeWebDavConfig();
          await writeData('a_data.json', {'items': 1});
          final backup = (await engine().createBackup())!;

          final result = await engine().restoreBackup(backup);

          expect(result.ok, isTrue);
          expect(readAutoSync(), isFalse);
        },
      );

      test('re-enables autoSync when restore fails before any write', () async {
        await writeWebDavConfig();
        final file = File(p.join(directory.path, 'broken.json'));
        await file.writeAsString('{not json');

        final result = await engine().restoreBackup(file);

        expect(result.ok, isFalse);
        expect(result.wroteAnything, isFalse);
        expect(readAutoSync(), isTrue);
      });

      test('leaves autoSync off when restore fails after a write', () async {
        await writeWebDavConfig();
        // The module write succeeds, then the image phase fails because the
        // `images` path is occupied by a regular file, so creating the
        // images directory throws.
        await File(p.join(directory.path, 'images')).writeAsBytes([0]);
        final file = File(p.join(directory.path, 'restore2.json'));
        await file.writeAsString(
          jsonEncode({
            '_backupFormat': 2,
            'a_data.json': jsonEncode({'items': 1}),
            '_imageRefs': {'images/x.png': '${'0' * 64}.png'},
          }),
        );

        final result = await engine().restoreBackup(file);

        expect(result.ok, isFalse);
        expect(result.wroteAnything, isTrue);
        expect(readAutoSync(), isFalse);
      });

      test('restores normally when no webdav config exists', () async {
        await writeData('a_data.json', {'items': 1});
        final backup = (await engine().createBackup())!;

        final result = await engine().restoreBackup(backup);

        expect(result.ok, isTrue);
        expect(
          await File(p.join(directory.path, 'webdav_config.json')).exists(),
          isFalse,
        );
      });

      test('does not touch config when autoSync is already off', () async {
        await writeWebDavConfig(autoSync: false);
        await writeData('a_data.json', {'items': 1});
        final backup = (await engine().createBackup())!;

        final result = await engine().restoreBackup(backup);

        expect(result.ok, isTrue);
        expect(readAutoSync(), isFalse);
      });

      test('does not toggle incomplete configs', () async {
        await File(p.join(directory.path, 'webdav_config.json')).writeAsString(
          jsonEncode(
            const WebDAVConfig(
              serverUrl: 'https://x.test',
              username: 'u',
              password: '',
              remotePath: '/MyApp',
              autoSync: true,
            ).toJson(),
          ),
        );
        await writeData('a_data.json', {'items': 1});
        final backup = (await engine().createBackup())!;

        final result = await engine().restoreBackup(backup);

        expect(result.ok, isTrue);
        expect(readAutoSync(), isTrue);
      });
    });
  });

  group('runAutoBackupIfNeeded', () {
    test('does nothing when disabled', () async {
      await writeData('a_data.json', {'items': 1});
      storage.config['autoBackupEnabled'] = false;

      await engine().runAutoBackupIfNeeded();

      expect(bundles(), isEmpty);
    });

    test('creates one backup per day', () async {
      await writeData('a_data.json', {'items': 1});
      storage.config['autoBackupEnabled'] = true;
      final instance = engine();

      await instance.runAutoBackupIfNeeded();
      clock.now = clock.now.add(const Duration(seconds: 1));
      await instance.runAutoBackupIfNeeded();

      expect(bundles(), hasLength(1));
    });

    test('retries when today only has a corrupt bundle', () async {
      await writeData('a_data.json', {'items': 1});
      storage.config['autoBackupEnabled'] = true;
      final corrupt = File(
        p.join(backupDir().path, 'backup_20260724_115959.json'),
      );
      await corrupt.parent.create(recursive: true);
      await corrupt.writeAsString('{not json');

      await engine().runAutoBackupIfNeeded();

      final all = bundles();
      expect(all, hasLength(2));
      expect(
        all.any((f) => p.basename(f.path) == 'backup_20260724_120000.json'),
        isTrue,
      );
    });

    test('backs up again on a later day', () async {
      await writeData('a_data.json', {'items': 1});
      storage.config['autoBackupEnabled'] = true;
      final instance = engine();

      await instance.runAutoBackupIfNeeded();
      clock.now = clock.now.add(const Duration(days: 1));
      await instance.runAutoBackupIfNeeded();

      expect(bundles(), hasLength(2));
    });
  });

  group('settings', () {
    test('loadSettings reads shared keys with defaults', () async {
      final instance = engine();
      await instance.loadSettings();
      expect(instance.autoBackupEnabled, isFalse);
      expect(instance.retentionDays, 0);

      storage.config['autoBackupEnabled'] = true;
      storage.config['backupRetentionDays'] = 30;
      await instance.loadSettings();
      expect(instance.autoBackupEnabled, isTrue);
      expect(instance.retentionDays, 30);
    });

    test('saveSettings preserves unrelated config keys', () async {
      storage.config['themeMode'] = 'dark';
      final instance = engine()
        ..autoBackupEnabled = true
        ..retentionDays = 7;

      await instance.saveSettings();

      expect(storage.config['autoBackupEnabled'], isTrue);
      expect(storage.config['backupRetentionDays'], 7);
      expect(storage.config['themeMode'], 'dark');
    });
  });

  test('BackupInfo.displaySize formats B/KB/MB', () {
    BackupInfo info(int size) =>
        BackupInfo(file: File('x'), date: DateTime(2026), sizeBytes: size);

    expect(info(512).displaySize, '512 B');
    expect(info(2048).displaySize, '2.0 KB');
    expect(info(3 * 1024 * 1024).displaySize, '3.0 MB');
  });
}
