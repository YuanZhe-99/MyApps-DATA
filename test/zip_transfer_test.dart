import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  late Directory destDir;
  late _TestStorage storage;
  late DateTime now;

  ZipTransfer engine({
    String archiveNamePrefix = 'myapp_export_',
    bool rejectUnknownEntries = true,
    bool strictUtf8 = true,
    bool validateBeforeWrite = true,
    bool atomicWrites = true,
    ModuleRegistry? modules,
    void Function()? onAfterImport,
  }) {
    return ZipTransfer(
      storage: storage,
      modules:
          modules ??
          ModuleRegistry([
            _module('a_data.json', 'a'),
            _module('b_data.json', 'b'),
          ]),
      archiveNamePrefix: archiveNamePrefix,
      rejectUnknownEntries: rejectUnknownEntries,
      strictUtf8: strictUtf8,
      validateBeforeWrite: validateBeforeWrite,
      atomicWrites: atomicWrites,
      onAfterImport: onAfterImport,
      clock: () => now,
    );
  }

  Future<void> writeData(String name, Object json) async {
    await File(p.join(directory.path, name)).writeAsString(jsonEncode(json));
  }

  Future<void> writeImage(String name, List<int> bytes) async {
    final file = File(p.join(directory.path, 'images', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<File> makeZip(Map<String, List<int>> entries, {String? name}) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final file = File(p.join(destDir.path, name ?? 'import.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  Future<List<String>> zipEntryNames(String path) async {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    return archive.files.where((f) => f.isFile).map((f) => f.name).toList();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zip_transfer_app');
    destDir = await Directory.systemTemp.createTemp('zip_transfer_dest');
    storage = _TestStorage(directory);
    now = DateTime(2026, 7, 24, 12);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
    if (await destDir.exists()) await destDir.delete(recursive: true);
  });

  group('exportZip', () {
    test(
      'bundles module files and images with the configured prefix',
      () async {
        await writeData('a_data.json', {'items': 1});
        await writeData('b_data.json', {'items': 2});
        await writeImage('cover.png', utf8.encode('image-bytes'));

        final path = await engine().exportZip(destDir.path);

        expect(path, isNotNull);
        expect(p.basename(path!), 'myapp_export_20260724_120000.zip');
        final names = await zipEntryNames(path);
        expect(names, ['a_data.json', 'b_data.json', 'images/cover.png']);
        final archive = ZipDecoder().decodeBytes(
          await File(path).readAsBytes(),
        );
        final dataEntry = archive.files.firstWhere(
          (f) => f.name == 'a_data.json',
        );
        expect(
          utf8.decode(dataEntry.content as List<int>),
          jsonEncode({'items': 1}),
        );
      },
    );

    test(
      'skips missing module files and never bundles config or backups',
      () async {
        await writeData('a_data.json', {'items': 1});
        await File(
          p.join(directory.path, 'storage_config.json'),
        ).writeAsString('{}');
        await File(
          p.join(directory.path, 'webdav_config.json'),
        ).writeAsString('{}');
        final backups = Directory(p.join(directory.path, 'backups'));
        await backups.create(recursive: true);
        await File(
          p.join(backups.path, 'backup_20260724_120000.json'),
        ).writeAsString('{}');

        final path = await engine().exportZip(destDir.path);

        expect(await zipEntryNames(path!), ['a_data.json']);
      },
    );

    test('preserves each app archive name prefix', () async {
      for (final prefix in [
        'myanime_export_',
        'myday_backup_',
        'mydevice_export_',
      ]) {
        final path = await engine(
          archiveNamePrefix: prefix,
        ).exportZip(destDir.path);
        expect(p.basename(path!), '${prefix}20260724_120000.zip');
      }
    });

    test('returns null when the destination is unwritable', () async {
      final path = await engine().exportZip(
        p.join(destDir.path, 'missing', 'dir'),
      );
      expect(path, isNull);
    });
  });

  group('importZip', () {
    test('round-trips an export into a wiped app directory', () async {
      await writeData('a_data.json', {'items': 1});
      await writeData('b_data.json', {'items': 2});
      await writeImage('cover.png', utf8.encode('image-bytes'));
      final path = (await engine().exportZip(destDir.path))!;
      await File(p.join(directory.path, 'a_data.json')).delete();
      await File(p.join(directory.path, 'b_data.json')).delete();
      await File(p.join(directory.path, 'images', 'cover.png')).delete();

      final ok = await engine().importZip(path);

      expect(ok, isTrue);
      expect(
        await File(p.join(directory.path, 'a_data.json')).readAsString(),
        jsonEncode({'items': 1}),
      );
      expect(
        await File(p.join(directory.path, 'b_data.json')).readAsString(),
        jsonEncode({'items': 2}),
      );
      expect(
        await File(p.join(directory.path, 'images', 'cover.png')).readAsBytes(),
        utf8.encode('image-bytes'),
      );
    });

    test('overwrites existing files', () async {
      await writeData('a_data.json', {'items': 1});
      final path = (await engine().exportZip(destDir.path))!;
      await writeData('a_data.json', {'items': 999});

      expect(await engine().importZip(path), isTrue);
      expect(
        await File(p.join(directory.path, 'a_data.json')).readAsString(),
        jsonEncode({'items': 1}),
      );
    });

    test('returns false for a missing file', () async {
      expect(
        await engine().importZip(p.join(destDir.path, 'nope.zip')),
        isFalse,
      );
    });

    test('lenient decoder treats junk bytes as an empty archive', () async {
      final file = File(p.join(destDir.path, 'junk.zip'));
      await file.writeAsBytes(utf8.encode('not a zip'));
      // package:archive v4 does not throw on junk input; the import finds no
      // file entries and succeeds vacuously, matching the apps' behavior.
      expect(await engine().importZip(file.path), isTrue);
      expect(
        await File(p.join(directory.path, 'a_data.json')).exists(),
        isFalse,
      );
    });

    test('accepts an empty archive without writing', () async {
      final file = await makeZip({});
      expect(await engine().importZip(file.path), isTrue);
    });

    group('traversal and unknown entries', () {
      test('rejects traversal entries and writes nothing', () async {
        final file = await makeZip({
          'a_data.json': utf8.encode(jsonEncode({'items': 1})),
          '../evil.json': utf8.encode('{}'),
        });

        expect(await engine().importZip(file.path), isFalse);
        expect(
          await File(p.join(directory.path, 'a_data.json')).exists(),
          isFalse,
        );
      });

      test('rejects image traversal entries', () async {
        final file = await makeZip({'images/../evil.png': utf8.encode('x')});

        expect(await engine().importZip(file.path), isFalse);
        expect(
          await File(p.join(directory.path, 'evil.png')).exists(),
          isFalse,
        );
      });

      test('rejects unknown entries by default', () async {
        final file = await makeZip({'webdav_config.json': utf8.encode('{}')});
        expect(await engine().importZip(file.path), isFalse);
      });

      test(
        'skips unknown entries when rejectUnknownEntries is false',
        () async {
          final file = await makeZip({
            'a_data.json': utf8.encode(jsonEncode({'items': 1})),
            'webdav_config.json': utf8.encode('{"hacked":true}'),
          });

          expect(
            await engine(
              rejectUnknownEntries: false,
              strictUtf8: false,
              validateBeforeWrite: false,
              atomicWrites: false,
            ).importZip(file.path),
            isTrue,
          );
          expect(
            await File(p.join(directory.path, 'a_data.json')).exists(),
            isTrue,
          );
          expect(
            await File(p.join(directory.path, 'webdav_config.json')).exists(),
            isFalse,
          );
        },
      );

      test('rejects nested image entries by default', () async {
        final file = await makeZip({'images/sub/x.png': utf8.encode('x')});
        expect(await engine().importZip(file.path), isFalse);
      });

      test('skips nested image entries in lenient mode', () async {
        final file = await makeZip({
          'a_data.json': utf8.encode(jsonEncode({'items': 1})),
          'images/sub/x.png': utf8.encode('x'),
        });

        expect(
          await engine(
            rejectUnknownEntries: false,
            strictUtf8: false,
            validateBeforeWrite: false,
            atomicWrites: false,
          ).importZip(file.path),
          isTrue,
        );
        expect(
          await Directory(p.join(directory.path, 'images', 'sub')).exists(),
          isFalse,
        );
      });

      test('skips directory entries', () async {
        final archive = Archive();
        archive.addFile(ArchiveFile('images/', 0, <int>[]));
        final file = File(p.join(destDir.path, 'import.zip'));
        await file.writeAsBytes(ZipEncoder().encode(archive));
        // The decoder reports `images/` as a non-file entry, so it is
        // skipped like every other directory entry (matching the apps).
        expect(await engine().importZip(file.path), isTrue);
      });
    });

    group('UTF-8 strictness and validation', () {
      test(
        'strictUtf8 rejects malformed data payloads before writing',
        () async {
          final file = await makeZip({
            'a_data.json': utf8.encode(jsonEncode({'items': 1})),
            'b_data.json': [0xFF, 0xFE, 0x00],
          });

          expect(await engine().importZip(file.path), isFalse);
          expect(
            await File(p.join(directory.path, 'a_data.json')).exists(),
            isFalse,
          );
          expect(
            await File(p.join(directory.path, 'b_data.json')).exists(),
            isFalse,
          );
        },
      );

      test('lenient mode writes raw bytes without decoding', () async {
        final payload = [0xFF, 0xFE, 0x00];
        final file = await makeZip({'b_data.json': payload});

        expect(
          await engine(
            rejectUnknownEntries: false,
            strictUtf8: false,
            validateBeforeWrite: false,
            atomicWrites: false,
          ).importZip(file.path),
          isTrue,
        );
        expect(
          await File(p.join(directory.path, 'b_data.json')).readAsBytes(),
          payload,
        );
      });

      test('validateBeforeWrite aborts before writing any file', () async {
        final modules = ModuleRegistry([
          _module('a_data.json', 'a'),
          _module(
            'b_data.json',
            'b',
            validate: (raw) =>
                throw DataFileValidationException('b_data.json', 'bad'),
          ),
        ]);
        final file = await makeZip({
          'a_data.json': utf8.encode(jsonEncode({'items': 1})),
          'b_data.json': utf8.encode(jsonEncode({'items': 2})),
        });

        expect(await engine(modules: modules).importZip(file.path), isFalse);
        expect(
          await File(p.join(directory.path, 'a_data.json')).exists(),
          isFalse,
        );
        expect(
          await File(p.join(directory.path, 'b_data.json')).exists(),
          isFalse,
        );
      });

      test(
        'validateBeforeWrite without strictUtf8 decodes tolerantly',
        () async {
          final modules = ModuleRegistry([
            _module('a_data.json', 'a', validate: (_) {}),
          ]);
          final file = await makeZip({
            'a_data.json': [0xFF, 0xFE],
          });

          expect(
            await engine(
              modules: modules,
              strictUtf8: false,
            ).importZip(file.path),
            isTrue,
          );
          expect(
            await File(p.join(directory.path, 'a_data.json')).readAsBytes(),
            [0xFF, 0xFE],
          );
        },
      );
    });

    group('write modes and hooks', () {
      test('plain write mode overwrites without atomic helpers', () async {
        final file = await makeZip({
          'a_data.json': utf8.encode(jsonEncode({'items': 1})),
          'images/pic.png': utf8.encode('png'),
        });

        expect(
          await engine(
            strictUtf8: false,
            validateBeforeWrite: false,
            atomicWrites: false,
          ).importZip(file.path),
          isTrue,
        );
        expect(
          await File(p.join(directory.path, 'a_data.json')).exists(),
          isTrue,
        );
        expect(
          await File(p.join(directory.path, 'images', 'pic.png')).exists(),
          isTrue,
        );
      });

      test('onAfterImport runs after success only', () async {
        var calls = 0;
        final good = await makeZip({
          'a_data.json': utf8.encode(jsonEncode({'items': 1})),
        });
        final bad = await makeZip({
          '../evil.json': utf8.encode('{}'),
        }, name: 'bad.zip');

        expect(
          await engine(onAfterImport: () => calls++).importZip(bad.path),
          isFalse,
        );
        expect(calls, 0);
        expect(
          await engine(onAfterImport: () => calls++).importZip(good.path),
          isTrue,
        );
        expect(calls, 1);
      });
    });
  });
}
