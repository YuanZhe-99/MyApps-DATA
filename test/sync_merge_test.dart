// Unit tests for the generic merge engine (P2.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

/// Minimal record used for merge tests.
class _Rec {
  final String id;
  final DateTime modifiedAt;
  final String? note;
  final Map<String, dynamic> extra;

  _Rec(this.id, this.modifiedAt, {this.note, this.extra = const {}});

  @override
  String toString() => '_Rec($id,$modifiedAt,note=$note,extra=$extra)';
}

DateTime _ts(String s) => DateTime.parse(s);

String _ser(_Rec r) =>
    '{"id":"${r.id}","note":"${r.note ?? ""}","modifiedAt":"${r.modifiedAt.toIso8601String()}"}';

void main() {
  group('mergeRecords - change detection', () {
    test('only local changed -> use local', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-03T00:00:00.000Z'), note: 'local')];
      final remote = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged.single.note, 'local');
      expect(r.conflicts, isEmpty);
    });

    test('only remote changed -> use remote', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final remote = [
        _Rec('1', _ts('2026-01-03T00:00:00.000Z'), note: 'remote'),
      ];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged.single.note, 'remote');
      expect(r.conflicts, isEmpty);
    });

    test('neither changed -> use local', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final remote = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged.single.note, 'base');
      expect(r.conflicts, isEmpty);
    });

    test('both changed identically -> no conflict', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final both = [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'same')];
      final r = mergeRecords(
        local: both,
        remote: both,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
        serialize: _ser,
      );
      expect(r.conflicts, isEmpty);
      expect(r.merged.single.note, 'same');
    });

    test('both changed differently -> conflict (autoResolve false)', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local')];
      final remote = [
        _Rec('1', _ts('2026-01-06T00:00:00.000Z'), note: 'remote'),
      ];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
        serialize: _ser,
      );
      expect(r.conflicts.length, 1);
      expect(r.conflicts.single.id, '1');
      expect(r.conflicts.single.localRecord.note, 'local');
      expect(r.conflicts.single.remoteRecord.note, 'remote');
      expect(r.merged, isEmpty);
    });

    test('both changed differently + autoResolve -> LWW newer wins', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local')];
      final remote = [
        _Rec('1', _ts('2026-01-06T00:00:00.000Z'), note: 'remote'),
      ];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
        autoResolve: true,
      );
      expect(r.conflicts, isEmpty);
      expect(r.merged.single.note, 'remote');
    });

    test('autoResolve ties go to remote', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'base')];
      final local = [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local')];
      final remote = [
        _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'remote'),
      ];
      final r = mergeRecords(
        local: local,
        remote: remote,
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
        autoResolve: true,
      );
      expect(r.merged.single.note, 'remote');
    });
  });

  group('mergeRecords - additions', () {
    test('new record on one side only -> include', () {
      final r = mergeRecords(
        local: [_Rec('L', _ts('2026-01-01T00:00:00.000Z'))],
        remote: [_Rec('R', _ts('2026-01-01T00:00:00.000Z'))],
        base: [],
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      final ids = r.merged.map((r) => r.id).toSet();
      expect(ids, {'L', 'R'});
    });

    test('no base, both added same id -> LWW (ties to remote)', () {
      final r = mergeRecords(
        local: [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local')],
        remote: [_Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'remote')],
        base: null,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged.single.note, 'remote');
    });
  });

  group('mergeRecords - deletion matrix (P0.1 E4)', () {
    test(
      'deleted locally, remote unchanged -> excluded (deletion propagates)',
      () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final remote = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final r = mergeRecords(
          local: [],
          remote: remote,
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
        );
        expect(r.merged, isEmpty);
      },
    );

    test(
      'deleted locally, remote modified -> keep remote (modify > delete)',
      () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final remote = [
          _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'remote'),
        ];
        final r = mergeRecords(
          local: [],
          remote: remote,
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
        );
        expect(r.merged.single.note, 'remote');
      },
    );

    test('deleted remotely, local unchanged -> excluded', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
      final local = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
      final r = mergeRecords(
        local: local,
        remote: [],
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged, isEmpty);
    });

    test(
      'deleted remotely, local modified -> keep local (modify > delete)',
      () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final local = [
          _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local'),
        ];
        final r = mergeRecords(
          local: local,
          remote: [],
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
        );
        expect(r.merged.single.note, 'local');
      },
    );

    test('deleted both sides -> excluded', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
      final r = mergeRecords(
        local: [],
        remote: [],
        base: base,
        getId: (r) => r.id,
        getModifiedAt: (r) => r.modifiedAt,
        getDisplayName: (r) => r.id,
      );
      expect(r.merged, isEmpty);
    });
  });

  group('mergeRecords - mergeUnknownFields callback', () {
    test(
      'callback is applied to merged/conflict records (MyDevice pattern)',
      () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final local = [
          _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local'),
        ];
        final remote = [
          _Rec('1', _ts('2026-01-06T00:00:00.000Z'), note: 'remote'),
        ];
        _Rec mergeUnknown(_Rec primary, _Rec secondary, _Rec? base) => _Rec(
          primary.id,
          primary.modifiedAt,
          note: primary.note,
          extra: {...secondary.extra, ...primary.extra},
        );

        final r = mergeRecords(
          local: local,
          remote: remote,
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
          mergeUnknownFields: mergeUnknown,
        );
        // Both sides changed differently -> conflict; callback wraps both sides.
        expect(r.conflicts.length, 1);
        expect(r.conflicts.single.localRecord.note, 'local');
        expect(r.conflicts.single.remoteRecord.note, 'remote');
      },
    );

    test(
      'without callback, primary is returned as-is (MyAnime/MyDay pattern)',
      () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final local = [
          _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'local'),
        ];
        final remote = [
          _Rec('1', _ts('2026-01-01T00:00:00.000Z'), note: 'remote'),
        ];
        final r = mergeRecords(
          local: local,
          remote: remote,
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
        );
        expect(r.merged.single.note, 'local');
        expect(r.merged.single.extra, isEmpty);
      },
    );
  });
}
