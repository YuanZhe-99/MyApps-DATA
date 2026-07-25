# lib/src/json/json_preservation.dart

Generic, schema-driven and flat-map JSON unknown-field preservation engines (P2.2). Extracted
from MyDay (schema-driven recursive walk) and MyDevice (flat `extraJson` three-way merge); both
styles are exported so each app keeps its existing preservation strategy. App field-name schemas
do NOT live here - they stay app-side and are passed in at call time.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `JsonListPreservation` | class | A | Describes how to match and preserve unknown fields in one list of objects. |
| `JsonPreservationSchema` | class | A | Describes the known shape of one JSON object level. |
| `JsonPreservation` | class (static utils) | A | Schema-driven recursive unknown-field preservation (MyDay style). |
| `unknownJsonFields` | function | A | Extract unknown keys from a map (MyDevice style). |
| `mergeUnknownJsonFields` | function | A | Three-way merge of unknown-field maps (MyDevice style). |
| `jsonValueEquals` | function | A | Canonical (key-sorted) JSON value equality. |

(Plus private helpers `_canonicalJson`, `_copyMap`, `_stringKeyMap`, `_copyJsonValue`.)

## Behavior

### Schema-driven engine (`JsonPreservation`)

- `preserve({next, sources, schema})` re-injects unknown keys from each source onto `next` in
  order, recursing into known `objectFields`, `keyedObjectFields`, and `listFields` (matched by
  `JsonListPreservation.keyField`).
- `preserveJsonString({...})` and `encodeForFile({...})` are string/file conveniences over
  `preserve`; malformed sources are ignored.
- Known keys always come from `next`; unknown keys come from sources.

### Flat-map engine (`unknownJsonFields` / `mergeUnknownJsonFields`)

- `unknownJsonFields(json, knownKeys)` returns only keys absent from `knownKeys`.
- `mergeUnknownJsonFields({primary, secondary, base})` per key:
  - both + base: if only secondary changed -> secondary, else primary;
  - both, no base -> primary;
  - one side only -> that side;
  - neither (base only) -> removed.
- `jsonValueEquals` compares by canonical (key-sorted) JSON encoding so map key order does not
  affect change detection.
