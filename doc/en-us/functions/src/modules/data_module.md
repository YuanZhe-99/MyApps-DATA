# lib/src/modules/data_module.dart

App-neutral module descriptors, merge outcomes, opaque conflicts, and the ordered registry that
replaces every hardcoded per-app data-file list.

## Declarations

The file documents 22 declarations: six callback typedefs, `DataFileValidationException`,
`ModuleWriteReason`, `ModuleUploadContext`, `ModuleConflict`, `ModuleMergeOutcome`, `DataModule`,
`ModuleRegistry`, their constructors, `DataFileValidationException.toString`, and
`ModuleMergeOutcome.resolve`.

## `DataFileValidationException`

Typed validation failure extracted from MyDay's `DataFileSafety` (feature-matrix §K8), carrying
`fileName` and `message`. Apps are encouraged to throw it from `validate` callbacks so backup
restore (P2.7) and ZIP import (P2.8) failures name the failing module file; any thrown value
aborts validation-before-write regardless of type.

## `DataModule`

Each descriptor supplies:

- `fileName`: persisted local/remote name, such as `anime_data.json`; never renamed.
- `moduleId`: persisted backup module key; never renamed.
- `validate`: app model parser for validation-oriented engines. P2.6 deliberately retains current
  sync compatibility: direct remote-only copies are raw and force download is syntax-only.
- `merge`: async-capable callback called only when local and remote both exist and raw strings
  differ. Missing-side and raw-equal branches never normalize the payload through app models.
- `postMergeTransform`: optional async transform after conflict-free merge and conflict resolution.
  MyDay finance uses this for forced-balance migration at its actual post-resolution position.
- `preUploadTransform`: optional final transform with base/local/remote context. MyDay uses this to
  call `JsonPreservation`; model-level preservation apps leave it null.
- `referencedImages`: optional app parser returning image basenames.
- `indexMergedUploadProgress`: whether a merged upload reports module index/total. It defaults
  true; MyDay structured modules set false to retain their current indeterminate phase.

Callbacks return final strings without package-side reformatting. This preserves MyDay's current
compact generated JSON while allowing MyAnime/MyDevice module callbacks to return pretty JSON.

## Merge outcomes

`ModuleMergeOutcome` supports two states:

- Conflict-free: `mergedJson` is required.
- Pending: `conflicts` and `buildResolvedJson` are required; `state` may retain an app-typed merge
  result so a P3 facade can rebuild its existing `PendingSync` fields.

`ModuleConflict` stores opaque local/remote app records, display name, existing record ID, and a
`resolutionKey`. The key defaults to the ID but can be namespaced for modules with multiple record
containers that can reuse IDs.

## `ModuleRegistry`

The registry freezes insertion order and provides lookup maps by `fileName` and `moduleId`. It
rejects empty or duplicate identifiers. Order is behaviorally significant: it controls WebDAV
request order, progress indices, partial-write order, conflict order, image-reference order, and
joined error order.
