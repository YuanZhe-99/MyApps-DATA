/// Purpose: Describe app-owned data files through app-neutral sync callbacks.
/// Inputs: Module descriptors supplied by each consuming app.
/// Returns: Ordered module lookup, merge outcomes, and opaque conflict state.
/// Side effects: Callbacks may parse models, migrate data, or preserve JSON.
/// Notes: The package never imports app models or hardcodes app file lists.
library;

import 'dart:async';
import 'dart:collection';

/// Typed validation failure thrown by [ModuleValidator] implementations.
///
/// Extracted from MyDay's `DataFileSafety` (feature-matrix §K8). Apps are
/// encouraged to throw this from their `validate` callbacks so backup
/// restore and ZIP import failures name the failing module file.
class DataFileValidationException implements Exception {
  /// Purpose: Create a data-file validation exception.
  /// Inputs: [fileName] failing module file, [message] failure detail.
  /// Returns: A new [DataFileValidationException].
  /// Side effects: None.
  /// Notes: Used to report import/restore failures without overwriting data.
  const DataFileValidationException(this.fileName, this.message);

  /// Module data-file name that failed validation.
  final String fileName;

  /// Human-readable validation failure detail.
  final String message;

  /// Purpose: Return a readable validation message.
  /// Inputs: None.
  /// Returns: `'$fileName: $message'`.
  /// Side effects: None.
  /// Notes: Includes the file name so UI can point at the failing module.
  @override
  String toString() => '$fileName: $message';
}

/// Purpose: Validate one module JSON payload.
/// Inputs: [json] raw module content.
/// Returns: None; throws when invalid.
/// Side effects: App-defined.
/// Notes: P2.6 retains current sync compatibility and uses syntax-only
/// validation for force download. Backup and ZIP engines use this callback.
typedef ModuleValidator = void Function(String json);

/// Purpose: Merge a differing local/remote module pair against an optional base.
/// Inputs: Raw [localJson], [remoteJson], optional [baseJson], [autoResolve].
/// Returns: A complete or pending [ModuleMergeOutcome].
/// Side effects: App-defined; may perform asynchronous migration work.
/// Notes: The engine invokes this only when local and remote files both exist
/// and their raw strings differ. Missing-side and raw-equal paths stay raw.
typedef ModuleMergeCallback =
    FutureOr<ModuleMergeOutcome> Function({
      required String localJson,
      required String remoteJson,
      required String? baseJson,
      required bool autoResolve,
    });

/// Purpose: Build complete resolved module JSON from user choices.
/// Inputs: [resolutions] keyed by [ModuleConflict.resolutionKey].
/// Returns: Complete module JSON ready for post-merge transforms.
/// Side effects: App-defined; may parse models or perform async migration.
/// Notes: Missing or wrong-typed choices retain each app's existing fallback
/// behavior inside the callback, normally choosing the local record.
typedef ModuleResolutionBuilder =
    FutureOr<String> Function(Map<String, Object?> resolutions);

/// Purpose: Apply app-specific work after merge or conflict resolution.
/// Inputs: [json] complete merged/resolved module JSON.
/// Returns: Transformed complete JSON.
/// Side effects: App-defined and may be asynchronous.
/// Notes: This models MyDay finance's async forced-balance migration at its
/// actual post-resolution position; it is not a pre-merge remote migration.
typedef ModulePostMergeTransform = FutureOr<String> Function(String json);

/// Purpose: Re-inject app-specific preservation data immediately before write.
/// Inputs: [context] containing next JSON and ordered source snapshots.
/// Returns: Final JSON to write locally and upload.
/// Side effects: App-defined.
/// Notes: MyDay uses this for schema-driven unknown-field preservation. Model-
/// based apps leave it null because their merge output is self-preserving.
typedef ModulePreUploadTransform =
    FutureOr<String> Function(ModuleUploadContext context);

/// Purpose: Extract referenced image basenames from module JSON.
/// Inputs: [json] raw or merged module JSON.
/// Returns: Referenced image basenames.
/// Side effects: None unless app-defined.
/// Notes: Callbacks should return an empty set for malformed input, matching
/// current app image-extraction behavior.
typedef ModuleImageReferences = Set<String> Function(String json);

/// Why a module payload is being prepared for local write and upload.
enum ModuleWriteReason { merge, finalize }

/// Ordered JSON snapshots supplied to a pre-upload preservation callback.
class ModuleUploadContext {
  /// Purpose: Create a module upload-transform context.
  /// Inputs: [nextJson], optional [baseJson]/[localJson]/[remoteJson], [reason].
  /// Returns: A new immutable context.
  /// Side effects: None.
  /// Notes: Normal merge provides base, final local, and downloaded remote.
  /// Finalize provides latest local and freshly downloaded remote, but no base.
  const ModuleUploadContext({
    required this.nextJson,
    required this.baseJson,
    required this.localJson,
    required this.remoteJson,
    required this.reason,
  });

  /// Complete app-generated JSON before preservation.
  final String nextJson;

  /// Last successful base snapshot, when applicable.
  final String? baseJson;

  /// Local snapshot used for preservation.
  final String? localJson;

  /// Remote snapshot used for preservation.
  final String? remoteJson;

  /// Current write path.
  final ModuleWriteReason reason;
}

/// App-neutral conflict carrying opaque app record values.
class ModuleConflict {
  /// Purpose: Create an app-neutral module conflict.
  /// Inputs: [id], local/remote records, [displayName], optional [resolutionKey].
  /// Returns: A new immutable conflict.
  /// Side effects: None.
  /// Notes: Use a namespaced [resolutionKey] when one module can have duplicate
  /// IDs across record containers; otherwise the record [id] is used.
  const ModuleConflict({
    required this.id,
    required this.localRecord,
    required this.remoteRecord,
    required this.displayName,
    String? resolutionKey,
  }) : resolutionKey = resolutionKey ?? id;

  /// Existing app record identifier.
  final String id;

  /// Opaque local app record exposed back to the app facade.
  final Object localRecord;

  /// Opaque remote app record exposed back to the app facade.
  final Object remoteRecord;

  /// App-provided nonlocalized display label.
  final String displayName;

  /// Key consumed by the module resolution builder.
  final String resolutionKey;
}

/// Result of one app-owned module merge.
class ModuleMergeOutcome {
  /// Purpose: Create a complete or pending merge outcome.
  /// Inputs: Optional [mergedJson], [conflicts], optional [buildResolvedJson]
  /// and opaque [state].
  /// Returns: A new immutable outcome.
  /// Side effects: None.
  /// Notes: A conflict-free outcome requires [mergedJson]. A pending outcome
  /// requires [buildResolvedJson]. [state] lets P3 facades rebuild existing
  /// app-typed PendingSync shapes without exposing app models to this package.
  ModuleMergeOutcome({
    this.mergedJson,
    this.conflicts = const [],
    this.buildResolvedJson,
    this.state,
  }) : assert(
         conflicts.isEmpty ? mergedJson != null : buildResolvedJson != null,
         'A complete merge needs mergedJson; conflicts need a resolver.',
       );

  /// Complete module JSON for a conflict-free merge.
  final String? mergedJson;

  /// Ordered unresolved conflicts.
  final List<ModuleConflict> conflicts;

  /// Callback that rebuilds complete JSON after conflict choices.
  final ModuleResolutionBuilder? buildResolvedJson;

  /// Opaque app merge state retained for typed facades.
  final Object? state;

  /// Purpose: Build complete JSON for this pending outcome.
  /// Inputs: [resolutions] keyed by conflict resolution key.
  /// Returns: Resolved complete module JSON.
  /// Side effects: Runs the app-provided resolution callback.
  /// Notes: Throws StateError when called for an outcome without a resolver.
  Future<String> resolve(Map<String, Object?> resolutions) async {
    final builder = buildResolvedJson;
    if (builder == null) {
      throw StateError('This module merge has no pending conflict resolver.');
    }
    return builder(resolutions);
  }
}

/// Descriptor for one syncable and backupable app data file.
class DataModule {
  /// Purpose: Create one app-owned data module descriptor.
  /// Inputs: Stable [fileName]/[moduleId], [validate], [merge], and optional
  /// transform/image callbacks.
  /// Returns: A new immutable descriptor.
  /// Side effects: None until callbacks are invoked.
  /// Notes: File names and module IDs are persisted compatibility contracts.
  const DataModule({
    required this.fileName,
    required this.moduleId,
    required this.validate,
    required this.merge,
    this.postMergeTransform,
    this.preUploadTransform,
    this.referencedImages,
    this.indexMergedUploadProgress = true,
  });

  /// Local and remote data-file name, unchanged from existing apps.
  final String fileName;

  /// Existing backup module key, unchanged from existing apps.
  final String moduleId;

  /// App model parser used by validation-oriented engines.
  final ModuleValidator validate;

  /// App-owned record or whole-file merge implementation.
  final ModuleMergeCallback merge;

  /// Optional async transform applied after merge and conflict resolution.
  final ModulePostMergeTransform? postMergeTransform;

  /// Optional final unknown-field preservation transform.
  final ModulePreUploadTransform? preUploadTransform;

  /// Optional referenced-image extractor.
  final ModuleImageReferences? referencedImages;

  /// Whether merged uploads report their registry index and total.
  ///
  /// MyAnime/MyDevice and MyDay exchange rates use indexed progress. MyDay's
  /// structured merge helper currently reports an indeterminate upload phase.
  final bool indexMergedUploadProgress;
}

/// Ordered, validated registry that replaces every hardcoded app file list.
class ModuleRegistry {
  /// Purpose: Create an ordered module registry.
  /// Inputs: [modules] in wire/progress/partial-write order.
  /// Returns: An immutable registry with file-name and module-ID lookup.
  /// Side effects: None.
  /// Notes: Throws ArgumentError for empty identifiers or duplicate file names
  /// or module IDs. Insertion order is behaviorally significant.
  factory ModuleRegistry(Iterable<DataModule> modules) {
    final ordered = List<DataModule>.unmodifiable(modules);
    final byFileName = <String, DataModule>{};
    final byModuleId = <String, DataModule>{};
    for (final module in ordered) {
      if (module.fileName.isEmpty || module.moduleId.isEmpty) {
        throw ArgumentError('Module fileName and moduleId must be non-empty.');
      }
      if (byFileName.containsKey(module.fileName)) {
        throw ArgumentError('Duplicate module fileName: ${module.fileName}');
      }
      if (byModuleId.containsKey(module.moduleId)) {
        throw ArgumentError('Duplicate module moduleId: ${module.moduleId}');
      }
      byFileName[module.fileName] = module;
      byModuleId[module.moduleId] = module;
    }
    return ModuleRegistry._(
      ordered,
      UnmodifiableMapView(byFileName),
      UnmodifiableMapView(byModuleId),
    );
  }

  /// Purpose: Store prevalidated immutable registry collections.
  /// Inputs: Ordered modules and both lookup maps.
  /// Returns: A new [ModuleRegistry].
  /// Side effects: None.
  /// Notes: Internal constructor used by the validating factory.
  const ModuleRegistry._(this.modules, this.byFileName, this.byModuleId);

  /// Modules in behaviorally significant sync order.
  final List<DataModule> modules;

  /// Module lookup by persisted data-file name.
  final Map<String, DataModule> byFileName;

  /// Module lookup by persisted backup module ID.
  final Map<String, DataModule> byModuleId;
}
