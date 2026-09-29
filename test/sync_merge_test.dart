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
    // Each row: base/local/remote (modifiedAt, note), autoResolve, expected
    // merged note. `_ts` days are all in January 2026.
    final cases =
        <
          ({
            String name,
            (String, String) base,
            (String, String) local,
            (String, String) remote,
            bool autoResolve,
            String expected,
          })
        >[
          (
            name: 'only local changed -> use local',
            base: ('2026-01-01', 'base'),
            local: ('2026-01-03', 'local'),
            remote: ('2026-01-01', 'base'),
            autoResolve: false,
            expected: 'local',
          ),
          (
            name: 'only remote changed -> use remote',
            base: ('2026-01-01', 'base'),
            local: ('2026-01-01', 'base'),
            remote: ('2026-01-03', 'remote'),
            autoResolve: false,
            expected: 'remote',
          ),
          (
            name: 'neither changed -> use local',
            base: ('2026-01-01', 'base'),
            local: ('2026-01-01', 'base'),
            remote: ('2026-01-01', 'base'),
            autoResolve: false,
            expected: 'base',
          ),
          (
            name: 'both changed differently + autoResolve -> LWW newer wins',
            base: ('2026-01-01', 'base'),
            local: ('2026-01-05', 'local'),
            remote: ('2026-01-06', 'remote'),
            autoResolve: true,
            expected: 'remote',
          ),
          (
            name: 'autoResolve ties go to remote',
            base: ('2026-01-01', 'base'),
            local: ('2026-01-05', 'local'),
            remote: ('2026-01-05', 'remote'),
            autoResolve: true,
            expected: 'remote',
          ),
        ];

    for (final c in cases) {
      test(c.name, () {
        _Rec rec((String, String) v) =>
            _Rec('1', _ts('${v.$1}T00:00:00.000Z'), note: v.$2);
        final r = mergeRecords(
          local: [rec(c.local)],
          remote: [rec(c.remote)],
          base: [rec(c.base)],
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
          autoResolve: c.autoResolve,
        );
        expect(r.merged.single.note, c.expected);
        expect(r.conflicts, isEmpty);
      });
    }

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
    // Each row: which side deleted, whether the surviving side modified the
    // record, and the note expected to survive (null = record excluded).
    final cases =
        <
          ({
            String name,
            bool localDeleted,
            bool survivorModified,
            String? kept,
          })
        >[
          (
            name: 'deleted locally, remote unchanged -> excluded',
            localDeleted: true,
            survivorModified: false,
            kept: null,
          ),
          (
            name: 'deleted locally, remote modified -> keep remote',
            localDeleted: true,
            survivorModified: true,
            kept: 'survivor',
          ),
          (
            name: 'deleted remotely, local unchanged -> excluded',
            localDeleted: false,
            survivorModified: false,
            kept: null,
          ),
          (
            name: 'deleted remotely, local modified -> keep local',
            localDeleted: false,
            survivorModified: true,
            kept: 'survivor',
          ),
        ];

    for (final c in cases) {
      test(c.name, () {
        final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
        final survivor = [
          c.survivorModified
              ? _Rec('1', _ts('2026-01-05T00:00:00.000Z'), note: 'survivor')
              : _Rec('1', _ts('2026-01-01T00:00:00.000Z')),
        ];
        final r = mergeRecords(
          local: c.localDeleted ? <_Rec>[] : survivor,
          remote: c.localDeleted ? survivor : <_Rec>[],
          base: base,
          getId: (r) => r.id,
          getModifiedAt: (r) => r.modifiedAt,
          getDisplayName: (r) => r.id,
        );
        if (c.kept == null) {
          expect(r.merged, isEmpty);
        } else {
          expect(r.merged.single.note, c.kept);
        }
      });
    }

    test('deleted both sides -> excluded', () {
      final base = [_Rec('1', _ts('2026-01-01T00:00:00.000Z'))];
      final r = mergeRecords(
        local: <_Rec>[],
        remote: <_Rec>[],
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
