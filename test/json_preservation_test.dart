// Unit tests for the JSON preservation engines (P2.2).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_data/myapps_data.dart';

void main() {
  group('JsonPreservation (schema-driven, MyDay style)', () {
    test('unknown top-level keys from source are preserved onto next', () {
      final schema = const JsonPreservationSchema(knownKeys: {'known'});
      final next = {'known': 1};
      final source = {'known': 9, 'futureField': 'x'};
      final result = JsonPreservation.preserve(
        next: next,
        sources: [source],
        schema: schema,
      );
      expect(result['known'], 1); // next wins for known keys
      expect(result['futureField'], 'x'); // unknown preserved
    });

    test('recurses into known object fields', () {
      final schema = const JsonPreservationSchema(
        knownKeys: {'outer'},
        objectFields: {
          'outer': JsonPreservationSchema(knownKeys: {'a'}),
        },
      );
      final next = {
        'outer': {'a': 1},
      };
      final source = {
        'outer': {'a': 9, 'futureNested': true},
      };
      final result = JsonPreservation.preserve(
        next: next,
        sources: [source],
        schema: schema,
      );
      expect((result['outer'] as Map)['a'], 1);
      expect((result['outer'] as Map)['futureNested'], true);
    });

    test('recurses into list fields matched by key', () {
      final schema = const JsonPreservationSchema(
        knownKeys: {'items'},
        listFields: {
          'items': JsonListPreservation(
            keyField: 'id',
            itemSchema: JsonPreservationSchema(knownKeys: {'id', 'name'}),
          ),
        },
      );
      final next = {
        'items': [
          {'id': '1', 'name': 'next'},
        ],
      };
      final source = {
        'items': [
          {'id': '1', 'name': 'src', 'futureItemField': 42},
        ],
      };
      final result = JsonPreservation.preserve(
        next: next,
        sources: [source],
        schema: schema,
      );
      final item = (result['items'] as List).single as Map;
      expect(item['name'], 'next');
      expect(item['futureItemField'], 42);
    });

    test('recurses into keyed object fields', () {
      final schema = const JsonPreservationSchema(
        knownKeys: {'map'},
        keyedObjectFields: {
          'map': JsonPreservationSchema(knownKeys: {'v'}),
        },
      );
      final next = {
        'map': {
          'k1': {'v': 1},
        },
      };
      final source = {
        'map': {
          'k1': {'v': 9, 'future': true},
        },
      };
      final result = JsonPreservation.preserve(
        next: next,
        sources: [source],
        schema: schema,
      );
      final v = (result['map'] as Map)['k1'] as Map;
      expect(v['v'], 1);
      expect(v['future'], true);
    });

    test('preserveJsonString round-trips through JSON', () {
      final schema = const JsonPreservationSchema(knownKeys: {'a'});
      final out = JsonPreservation.preserveJsonString(
        nextJson: '{"a":1}',
        sourceJsons: ['{"a":9,"future":"x"}'],
        schema: schema,
      );
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['a'], 1);
      expect(decoded['future'], 'x');
    });

    test('malformed source strings are ignored', () {
      final schema = const JsonPreservationSchema(knownKeys: {'a'});
      final out = JsonPreservation.preserveJsonString(
        nextJson: '{"a":1}',
        sourceJsons: [null, '{bad', '{"future":2}'],
        schema: schema,
      );
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['a'], 1);
      expect(decoded['future'], 2);
    });

    test('multiple sources are applied in order', () {
      final schema = const JsonPreservationSchema(knownKeys: {'a'});
      final out = JsonPreservation.preserve(
        next: {'a': 1},
        sources: [
          {'future': 'src1'},
          {'future': 'src2'},
        ],
        schema: schema,
      );
      // Later source overwrites earlier for unknown keys.
      expect(out['future'], 'src2');
    });
  });

  group('flat-map preservation (MyDevice style)', () {
    test('unknownJsonFields extracts only unknown keys', () {
      final extra = unknownJsonFields(
        {'id': '1', 'name': 'x', 'futureField': 5},
        {'id', 'name'},
      );
      expect(extra, {'futureField': 5});
    });

    test('mergeUnknownJsonFields resolves each presence/change case', () {
      // Each row: primary, secondary, base (null = no base), expected value of
      // key `k` (null expected = key removed).
      final cases =
          <
            ({
              String name,
              Map<String, dynamic> primary,
              Map<String, dynamic> secondary,
              Map<String, dynamic>? base,
              Object? expected,
            })
          >[
            (
              name: 'both present, only secondary changed -> secondary wins',
              primary: {'k': 'base'},
              secondary: {'k': 'secondary'},
              base: {'k': 'base'},
              expected: 'secondary',
            ),
            (
              name: 'both present, primary changed -> primary wins',
              primary: {'k': 'primaryNew'},
              secondary: {'k': 'secondary'},
              base: {'k': 'base'},
              expected: 'primaryNew',
            ),
            (
              name: 'both present without base -> primary wins',
              primary: {'k': 'p'},
              secondary: {'k': 's'},
              base: null,
              expected: 'p',
            ),
            (
              name: 'only primary has it -> primary wins',
              primary: {'k': 'p'},
              secondary: {},
              base: null,
              expected: 'p',
            ),
            (
              name: 'only secondary has it -> secondary wins',
              primary: {},
              secondary: {'k': 's'},
              base: null,
              expected: 's',
            ),
            (
              name: 'neither has it (base only) -> removed',
              primary: {},
              secondary: {},
              base: {'k': 'old'},
              expected: null,
            ),
          ];

      for (final c in cases) {
        final result = mergeUnknownJsonFields(
          primary: c.primary,
          secondary: c.secondary,
          base: c.base,
        );
        if (c.expected == null) {
          expect(result.containsKey('k'), isFalse, reason: c.name);
        } else {
          expect(result['k'], c.expected, reason: c.name);
        }
      }
    });

    test('jsonValueEquals sorts map keys before comparing', () {
      expect(jsonValueEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(jsonValueEquals({'a': 1}, {'a': 2}), isFalse);
      expect(jsonValueEquals([1, 2], [1, 2]), isTrue);
      expect(jsonValueEquals([1, 2], [2, 1]), isFalse);
    });
  });

  group('JsonPreservation.preserve output contract', () {
    const schema = JsonPreservationSchema(
      knownKeys: {'meta', 'tasks', 'accounts', 'title'},
      objectFields: {
        'meta': JsonPreservationSchema(knownKeys: {'v'}),
      },
      listFields: {
        'tasks': JsonListPreservation(
          keyField: 'id',
          itemSchema: JsonPreservationSchema(
            knownKeys: {'id', 'name', 'sub'},
            objectFields: {
              'sub': JsonPreservationSchema(knownKeys: {'k'}),
            },
          ),
        ),
      },
      keyedObjectFields: {
        'accounts': JsonPreservationSchema(knownKeys: {'bal'}),
      },
    );

    Map<String, dynamic> nextFixture() => {
      'title': 'T',
      'meta': {'v': 2},
      'tasks': [
        {
          'id': 1,
          'name': 'a',
          'sub': {'k': 1},
        },
        {'id': 2, 'name': 'b'},
        'scalar',
        {'name': 'no-id'},
      ],
      'accounts': {
        'x': {'bal': 5},
        'y': {'bal': 6},
        'z': 7,
      },
    };

    Map<String, dynamic> source1Fixture() => {
      'title': 'old',
      'future1': {
        'deep': [
          1,
          {'a': null},
        ],
      },
      'meta': {
        'v': 1,
        'mf': [true],
      },
      'tasks': [
        {
          'id': 1,
          'name': 'old',
          'tf': {
            'q': [1, 2],
          },
          'sub': {'k': 0, 'sf': 'z'},
        },
        {'id': 3, 'name': 'gone', 'tf': 1},
      ],
      'accounts': {
        'x': {'bal': 1, 'af': 'x1'},
        'w': {'bal': 9},
      },
    };

    Map<String, dynamic> source2Fixture() => {
      'future2': 3.5,
      'tasks': [
        {'id': 2, 'name': 'o2', 'tf2': 'two'},
      ],
      'accounts': {
        'y': {
          'af': [1],
        },
      },
    };

    test('output is byte-identical to the recorded fixture', () {
      final result = JsonPreservation.preserve(
        next: nextFixture(),
        sources: [source1Fixture(), source2Fixture()],
        schema: schema,
      );
      // Recorded from the pre-1.0.3 deep-copying implementation.
      expect(
        jsonEncode(result),
        '{"title":"T","meta":{"v":2,"mf":[true]},'
        '"tasks":[{"id":1,"name":"a","sub":{"k":1,"sf":"z"},"tf":{"q":[1,2]}},'
        '{"id":2,"name":"b","tf2":"two"},"scalar",{"name":"no-id"}],'
        '"accounts":{"x":{"bal":5,"af":"x1"},"y":{"bal":6,"af":[1]},"z":7},'
        '"future1":{"deep":[1,{"a":null}]},"future2":3.5}',
      );
    });

    test('result shares no mutable structure with next or the sources', () {
      final next = nextFixture();
      final s1 = source1Fixture();
      final s2 = source2Fixture();
      final result = JsonPreservation.preserve(
        next: next,
        sources: [s1, s2],
        schema: schema,
      );

      // Mutate every container reachable from the result.
      void scramble(dynamic v) {
        if (v is Map) {
          for (final child in v.values.toList()) {
            scramble(child);
          }
          v['__mutated'] = true;
        } else if (v is List) {
          for (final child in v.toList()) {
            scramble(child);
          }
          v.add('__mutated');
        }
      }

      scramble(result);

      expect(jsonEncode(next), jsonEncode(nextFixture()));
      expect(jsonEncode(s1), jsonEncode(source1Fixture()));
      expect(jsonEncode(s2), jsonEncode(source2Fixture()));
    });
  });
}
