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

    test(
      'mergeUnknownJsonFields: both present with base, only secondary changed -> secondary wins',
      () {
        final result = mergeUnknownJsonFields(
          primary: {'k': 'base'}, // primary unchanged from base
          secondary: {'k': 'secondary'}, // secondary changed
          base: {'k': 'base'},
        );
        expect(result['k'], 'secondary');
      },
    );

    test(
      'mergeUnknownJsonFields: both present with base, primary changed -> primary wins',
      () {
        final result = mergeUnknownJsonFields(
          primary: {'k': 'primaryNew'},
          secondary: {'k': 'secondary'},
          base: {'k': 'base'},
        );
        expect(result['k'], 'primaryNew');
      },
    );

    test(
      'mergeUnknownJsonFields: both present without base -> primary wins',
      () {
        final result = mergeUnknownJsonFields(
          primary: {'k': 'p'},
          secondary: {'k': 's'},
        );
        expect(result['k'], 'p');
      },
    );

    test('mergeUnknownJsonFields: only one side has it -> that side wins', () {
      expect(
        mergeUnknownJsonFields(primary: {'k': 'p'}, secondary: {})['k'],
        'p',
      );
      expect(
        mergeUnknownJsonFields(primary: {}, secondary: {'k': 's'})['k'],
        's',
      );
    });

    test('mergeUnknownJsonFields: neither has it (base only) -> removed', () {
      final result = mergeUnknownJsonFields(
        primary: {},
        secondary: {},
        base: {'k': 'old'},
      );
      expect(result.containsKey('k'), isFalse);
    });

    test('jsonValueEquals sorts map keys before comparing', () {
      expect(jsonValueEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(jsonValueEquals({'a': 1}, {'a': 2}), isFalse);
      expect(jsonValueEquals([1, 2], [1, 2]), isTrue);
      expect(jsonValueEquals([1, 2], [2, 1]), isFalse);
    });
  });
}
