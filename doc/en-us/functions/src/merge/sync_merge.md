# lib/src/merge/sync_merge.dart

Generic three-way record merge engine (P2.3). Unifies the MyAnime/MyDay/MyDevice
`mergeRecords<T>` variants: MyAnime and MyDay are byte-identical; MyDevice is a strict superset
adding an optional `mergeUnknownFields` callback (adopted here). App-specific merge wrappers and
`mergeAssignments` stay app-side.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `RecordConflict<T>` | class | A | One record-level conflict (same ID, both sides changed). |
| `RecordMergeResult<T>` | class | A | Merged list plus unresolved conflicts. |
| `mergeRecords<T>` | function | A | Three-way merge records by ID using `modifiedAt`. |

## Behavior (pinned by P0.1 matrix §E)

For each ID, using `base` to detect which side changed:

| Scenario | Result | Conflict? |
|---|---|---|
| Only local changed | local | No |
| Only remote changed | remote | No |
| Both changed, identical serialized content | local | No |
| Both changed, different content | conflict (or LWW if `autoResolve`) | Yes (unless autoResolve) |
| Neither changed | local | No |
| New on one side only | include it | No |
| Deleted one side, unchanged other | exclude (deletion propagates) | No |
| Deleted one side, modified other | keep the modification | No |
| Deleted both sides | exclude | No |
| No base, both added same ID | LWW by `modifiedAt` (ties -> remote) | No |

- `autoResolve` defaults to `false` (PLAN invariant I4).
- `serialize` (optional) enables identical-content conflict suppression.
- `mergeUnknownFields` (optional, MyDevice pattern) lets apps with model-level `extraJson`
  preserve unknown fields through the merge; without it, the primary record is returned as-is
  (MyAnime/MyDay pattern).
