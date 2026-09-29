import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';
import 'package:path/path.dart' as p;

/// Purpose: Exercise P2.4 atomic replacement and serialized queue behavior.
/// Inputs: None.
/// Returns: None.
/// Side effects: Creates and deletes isolated temporary directories.
/// Notes: Uses real filesystem operations so rename and cleanup semantics are
/// characterized on the host platform.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('myapps_atomic_io_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Purpose: List temporary atomic-write files below the test directory.
  /// Inputs: None.
  /// Returns: All files whose basename contains `.tmp-`.
  /// Side effects: Reads the temporary directory tree.
  /// Notes: Successful writes and handled failures must leave this empty.
  List<File> temporaryFiles() {
    return tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.basename(file.path).contains('.tmp-'))
        .toList();
  }

  group('atomicWriteString', () {
    test('creates parent directories and writes UTF-8 text', () async {
      final file = File(p.join(tempDir.path, 'nested', 'data.json'));

      await atomicWriteString(file, '{"title":"测试"}');

      expect(await file.readAsString(), '{"title":"测试"}');
      expect(temporaryFiles(), isEmpty);
    });

    test('replaces an existing destination completely', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString('old-longer-content');

      await atomicWriteString(file, 'new');

      expect(await file.readAsString(), 'new');
      expect(temporaryFiles(), isEmpty);
    });

    test(
      'rename failure preserves destination and cleans temporary file',
      () async {
        // A file cannot be renamed over an existing directory. This reliably
        // exercises the post-write rename failure path on supported platforms.
        final destination = Directory(p.join(tempDir.path, 'destination'));
        await destination.create();
        final file = File(destination.path);

        await expectLater(
          atomicWriteString(file, 'replacement'),
          throwsA(
            isA<FileSystemException>()
                .having((error) => error.path, 'path', file.path)
                .having(
                  (error) => error.message,
                  'message',
                  contains('Failed to replace file safely'),
                ),
          ),
        );

        expect(await destination.exists(), isTrue);
        expect(temporaryFiles(), isEmpty);
      },
    );
  });

  group('atomicWriteBytes', () {
    test('creates parents and replaces binary content', () async {
      final file = File(p.join(tempDir.path, 'images', 'cover.bin'));

      await atomicWriteBytes(file, [1, 2, 3, 255]);
      expect(await file.readAsBytes(), [1, 2, 3, 255]);

      await atomicWriteBytes(file, [9, 8]);
      expect(await file.readAsBytes(), [9, 8]);
      expect(temporaryFiles(), isEmpty);
    });

    test('rename failure is wrapped and cleans temporary file', () async {
      final destination = Directory(p.join(tempDir.path, 'binary-target'));
      await destination.create();
      final file = File(destination.path);

      await expectLater(
        atomicWriteBytes(file, [1, 2, 3]),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.path,
            'path',
            file.path,
          ),
        ),
      );

      expect(await destination.exists(), isTrue);
      expect(temporaryFiles(), isEmpty);
    });
  });

  group('AtomicWriteQueue', () {
    test('runs writes strictly in submission order', () async {
      final queue = AtomicWriteQueue();
      final firstGate = Completer<void>();
      final events = <String>[];

      final first = queue.enqueue(() async {
        events.add('first-start');
        await firstGate.future;
        events.add('first-end');
      });
      final second = queue.enqueue(() async {
        events.add('second-start');
        events.add('second-end');
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-start']);

      firstGate.complete();
      await Future.wait([first, second]);
      expect(events, [
        'first-start',
        'first-end',
        'second-start',
        'second-end',
      ]);
      await queue.idle;
    });

    test(
      'reports an operation error but continues with later writes',
      () async {
        final queue = AtomicWriteQueue();
        var secondRan = false;

        final first = queue.enqueue(() async {
          throw StateError('first failed');
        });
        final firstExpectation = expectLater(first, throwsStateError);
        final second = queue.enqueue(() async {
          secondRan = true;
        });

        await firstExpectation;
        await second;
        await queue.idle;
        expect(secondRan, isTrue);
      },
    );

    test('supports queued atomic writes to the same destination', () async {
      final queue = AtomicWriteQueue();
      final file = File(p.join(tempDir.path, 'queued.json'));

      final writes = [
        queue.enqueue(() => atomicWriteString(file, 'one')),
        queue.enqueue(() => atomicWriteString(file, 'two')),
        queue.enqueue(() => atomicWriteString(file, 'three')),
      ];
      await Future.wait(writes);

      expect(await file.readAsString(), 'three');
      expect(temporaryFiles(), isEmpty);
    });
  });

  group('temporary file names', () {
    test(
      'concurrent unserialized writes to different files never collide',
      () async {
        final files = [
          for (var i = 0; i < 40; i++) File(p.join(tempDir.path, 'f$i.json')),
        ];

        await Future.wait([
          for (var i = 0; i < files.length; i++)
            atomicWriteString(files[i], 'string-$i'),
          for (var i = 0; i < files.length; i++)
            atomicWriteBytes(File('${files[i].path}.bin'), [i]),
        ]);

        for (var i = 0; i < files.length; i++) {
          expect(await files[i].readAsString(), 'string-$i');
          expect(await File('${files[i].path}.bin').readAsBytes(), [i]);
        }
        expect(temporaryFiles(), isEmpty);
      },
    );

    test(
      'concurrent writes to one path leave one intact result and no temps',
      () async {
        // Writers starting in the same microsecond window used to share a temp
        // name; the per-process sequence number now keeps them apart, so a
        // loser can no longer clobber another writer's half-written temp.
        final file = File(p.join(tempDir.path, 'shared.dat'));
        final results = await Future.wait([
          for (var i = 0; i < 10; i++)
            atomicWriteBytes(file, [
              i,
            ]).then((_) => true, onError: (_) => false),
        ]);

        // Rename-over-existing can transiently fail on Windows when another
        // rename holds the target; what matters is no corruption or leftovers.
        expect(results.any((ok) => ok), isTrue);
        final content = await file.readAsBytes();
        expect(content, hasLength(1));
        expect(temporaryFiles(), isEmpty);
      },
    );
  });
}
