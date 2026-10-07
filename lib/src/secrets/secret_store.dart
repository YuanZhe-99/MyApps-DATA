/// Purpose: Read and write one application's local API-key secrets file.
/// Inputs: The app's [StorageAdapter], the file name the app injects, and the
/// key namespaces the app owns.
/// Returns: [SecretStore], its in-app lock, and the typed read failure.
/// Side effects: Reads, writes, renames and deletes the secrets file in the
/// active app directory.
/// Notes: The file sits beside the data files so a storage-path change carries
/// it along, but it is never a data module: the sync, backup and ZIP engines
/// only touch registry file names, so keys never enter a backup bundle or a ZIP
/// export. Keys are stored in plain text, like the WebDAV password.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/atomic_io.dart';
import '../storage/storage_adapter.dart';
import 'secrets_document.dart';

/// The secrets file exists but could not be read for an I/O reason.
///
/// Never thrown for bad content — that is set aside instead. The file may be
/// intact and merely locked, so nothing was written. Extends
/// [FileSystemException] so existing `on FileSystemException` handlers keep
/// working.
class SecretsUnreadableException extends FileSystemException {
  /// Purpose: Create the exception.
  /// Inputs: [message], the file [path] and the underlying [osError].
  /// Returns: A new exception.
  /// Side effects: None.
  /// Notes: None.
  const SecretsUnreadableException(super.message, [super.path, super.osError]);
}

/// One application's secrets file, restricted to the namespaces it owns.
class SecretStore {
  /// In-app locks by file name, shared by every store over the same file.
  static final Map<String, AtomicWriteQueue> _locks = {};

  /// Purpose: Create a store over one secrets file.
  /// Inputs: [storage] resolving the active app directory; [fileName] the
  /// app-injected file name (for example `transcribe_secrets.json`);
  /// [namespaces] the id prefixes this app may use; optional [onSaved] called
  /// after every non-quiet write (typically schedules auto-sync); optional
  /// [clock] for tests.
  /// Returns: A new [SecretStore].
  /// Side effects: None.
  /// Notes: Throws [ArgumentError] when [fileName] is blank or contains a path
  /// separator, or when [namespaces] is empty or holds a blank or `:` value.
  /// An id belongs to namespace `ns` when it starts with `ns:`.
  SecretStore({
    required this.storage,
    required this.fileName,
    required Set<String> namespaces,
    this.onSaved,
    DateTime Function()? clock,
  }) : namespaces = Set.unmodifiable(namespaces),
       _clock = clock ?? DateTime.now {
    if (fileName.trim().isEmpty ||
        fileName.contains('/') ||
        fileName.contains(r'\')) {
      throw ArgumentError.value(fileName, 'fileName', 'must be a bare name');
    }
    if (namespaces.isEmpty) {
      throw ArgumentError.value(namespaces, 'namespaces', 'must not be empty');
    }
    for (final ns in namespaces) {
      if (ns.trim().isEmpty || ns.contains(':')) {
        throw ArgumentError.value(ns, 'namespaces', 'invalid namespace');
      }
    }
  }

  /// Resolves the active app directory.
  final StorageAdapter storage;

  /// The secrets file name inside the app directory, and on the server.
  final String fileName;

  /// The id prefixes this app may read and write.
  final Set<String> namespaces;

  /// Called after [save] and [setKey]; never after [saveQuiet].
  final void Function()? onSaved;

  /// Source of `updatedAt` for [setKey].
  final DateTime Function() _clock;

  /// Purpose: Return the lock shared by every store over [fileName].
  /// Inputs: None.
  /// Returns: The [AtomicWriteQueue] for this file name.
  /// Side effects: Creates the queue on first use.
  /// Notes: Internal helper.
  AtomicWriteQueue get _lock =>
      _locks.putIfAbsent(fileName, () => AtomicWriteQueue());

  /// Purpose: Report whether [id] belongs to one of this app's namespaces.
  /// Inputs: [id].
  /// Returns: True when [id] is `<namespace>:<rest>` with a declared namespace
  /// and non-empty rest.
  /// Side effects: None.
  /// Notes: None.
  bool ownsId(String id) {
    final colon = id.indexOf(':');
    if (colon <= 0 || colon == id.length - 1) return false;
    return namespaces.contains(id.substring(0, colon));
  }

  /// Purpose: Reject an id outside this app's namespaces.
  /// Inputs: [id].
  /// Returns: None.
  /// Side effects: Throws [ArgumentError] for a foreign id.
  /// Notes: Internal helper.
  void _checkId(String id) {
    if (!ownsId(id)) {
      throw ArgumentError.value(id, 'id', 'not in namespaces $namespaces');
    }
  }

  /// Purpose: Locate the secrets file in the active app directory.
  /// Inputs: None.
  /// Returns: The [File].
  /// Side effects: The adapter may create the app directory.
  /// Notes: Resolved per call so a storage-path change is honoured.
  Future<File> file() async {
    final dir = await storage.getAppDir();
    return File(p.join(dir.path, fileName));
  }

  /// Purpose: Read the file for display or a request, never for a write.
  /// Inputs: None.
  /// Returns: The document; empty when absent, blank, unparseable or
  /// unreadable.
  /// Side effects: Reads the file.
  /// Notes: Tolerant on purpose: an empty result costs re-entering a key, and
  /// refusing to start over it would be worse. Never use it for the read half
  /// of a write — use [loadForWrite].
  Future<SecretsDocument> load() async {
    try {
      final f = await file();
      if (!await f.exists()) return SecretsDocument();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return SecretsDocument();
      return SecretsDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SecretsDocument();
    }
  }

  /// Purpose: Read the file for a change that will be written back.
  /// Inputs: None.
  /// Returns: The document; empty when absent or blank, or after setting
  /// unparseable content aside.
  /// Side effects: Reads the file; renames unparseable content to
  /// `<fileName>.unreadable-<UTC timestamp>`. Throws
  /// [SecretsUnreadableException] on an I/O error, including a failed rename.
  /// Notes: Call inside [withLock]. Content that is not UTF-8, not JSON or not
  /// a JSON object is bad content; anything the file system reports, and a
  /// non-file (such as a directory) at the path, is not.
  Future<SecretsDocument> loadForWrite() async {
    final f = await file();
    String raw;
    try {
      final type = await FileSystemEntity.type(f.path);
      if (type == FileSystemEntityType.notFound) return SecretsDocument();
      if (type != FileSystemEntityType.file) {
        throw SecretsUnreadableException('Secrets path is not a file', f.path);
      }
      final bytes = await f.readAsBytes();
      try {
        raw = utf8.decode(bytes);
      } on FormatException {
        await _setAside(f);
        return SecretsDocument();
      }
    } on SecretsUnreadableException {
      rethrow;
    } on FileSystemException catch (e) {
      throw SecretsUnreadableException(
        'Could not read secrets file: ${e.message}',
        f.path,
        e.osError,
      );
    }
    if (raw.trim().isEmpty) return SecretsDocument();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) {
      return SecretsDocument.fromJson(decoded);
    }
    await _setAside(f);
    return SecretsDocument();
  }

  /// Purpose: Move unparseable content out of the way so it can be recovered.
  /// Inputs: The unreadable file [f].
  /// Returns: The new path.
  /// Side effects: Renames [f] in place; throws [SecretsUnreadableException]
  /// when the rename fails.
  /// Notes: Internal helper. The timestamp is UTC ISO-8601 with `-`, `:` and
  /// `.` removed, matching MyTranscribe (`20261006T101500123456Z`).
  Future<String> _setAside(File f) async {
    final stamp = _clock()
        .toUtc()
        .toIso8601String()
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceAll('.', '');
    final target = '${f.path}.unreadable-$stamp';
    try {
      await f.rename(target);
    } on FileSystemException catch (e) {
      throw SecretsUnreadableException(
        'Could not set aside unreadable secrets file: ${e.message}',
        f.path,
        e.osError,
      );
    }
    return target;
  }

  /// Purpose: Run a read-modify-write of the secrets file without interleaving.
  /// Inputs: [action], which should read with [loadForWrite] and write with
  /// [save] or [saveQuiet].
  /// Returns: What [action] returns, or its error.
  /// Side effects: Whatever [action] does.
  /// Notes: Serialises with every store over the same file name in this
  /// process. Never make a network call inside [action], and never call
  /// [withLock], [setKey] or [deleteAll] from it: the lock is not re-entrant.
  Future<T> withLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock.enqueue(() async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Purpose: Write the document and notify the app.
  /// Inputs: [document].
  /// Returns: A future completing after the write.
  /// Side effects: Atomically replaces the file, then calls [onSaved].
  /// Notes: Use [saveQuiet] for writes that came from an exchange.
  Future<void> save(SecretsDocument document) async {
    await saveQuiet(document);
    onSaved?.call();
  }

  /// Purpose: Write the document without notifying the app.
  /// Inputs: [document].
  /// Returns: A future completing after the write.
  /// Side effects: Atomically replaces the file.
  /// Notes: Encoded with [encodeSecretsDocument].
  Future<void> saveQuiet(SecretsDocument document) async {
    await atomicWriteString(await file(), encodeSecretsDocument(document));
  }

  /// Purpose: Read one key.
  /// Inputs: [id] in one of this app's namespaces.
  /// Returns: The key, or null when absent, a tombstone or unreadable.
  /// Side effects: Reads the file; throws [ArgumentError] for a foreign id.
  /// Notes: Reads from disk each time, so a changed key applies on the next
  /// request and is not cached in memory.
  Future<String?> keyFor(String id) async {
    _checkId(id);
    return (await load()).keyFor(id);
  }

  /// Purpose: Set or clear one key.
  /// Inputs: [id] in one of this app's namespaces; [apiKey] (null or blank
  /// clears it).
  /// Returns: A future completing after the write.
  /// Side effects: Writes the file under [withLock] and calls [onSaved].
  /// Throws [ArgumentError] for a foreign id and [SecretsUnreadableException]
  /// on an I/O error, leaving the file untouched.
  /// Notes: Clearing writes a tombstone so the deletion propagates.
  Future<void> setKey(String id, String? apiKey) {
    _checkId(id);
    return withLock(() async {
      final current = await loadForWrite();
      await save(current.withKey(id, apiKey, now: _clock()));
    });
  }

  /// Purpose: List this app's ids that hold a usable key.
  /// Inputs: None.
  /// Returns: Ids only, never key values.
  /// Side effects: Reads the file.
  /// Notes: Ids outside [namespaces] are not reported.
  Future<Set<String>> configuredIds() async => {
    for (final id in (await load()).configuredIds)
      if (ownsId(id)) id,
  };

  /// Purpose: Forget every key on this device.
  /// Inputs: None.
  /// Returns: A future completing after deletion.
  /// Side effects: Deletes the file under [withLock].
  /// Notes: Leaves no tombstones, so a later exchange brings remote keys back —
  /// intended for handing a device on.
  Future<void> deleteAll() => withLock(() async {
    final f = await file();
    if (await f.exists()) await f.delete();
  });
}
