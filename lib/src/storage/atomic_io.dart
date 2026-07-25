/// Purpose: Shared atomic file-replacement helpers and an optional serialized
/// write queue extracted from the three apps.
/// Inputs: Destination files plus string/byte replacement content.
/// Returns: Futures that complete after replacement or report the write error.
/// Side effects: Creates parent directories, writes same-directory temporary
/// files, and renames them over destination files.
/// Notes: P2.4 follows the P0.1 matrix: unique `.tmp-<microseconds>` names,
/// `flush: true`, cleanup on failure, and a `FileSystemException` naming the
/// destination. No fsync is requested because none of the apps uses it today.
library;

import 'dart:io';

/// Purpose: Atomically replace [file] with UTF-8 [content] through a
/// same-directory temporary file.
/// Inputs: [file], [content].
/// Returns: A future completing after the destination is replaced.
/// Side effects: Creates the parent directory when needed, writes a temporary
/// file with `flush: true`, then renames it over [file].
/// Notes: On any failure, the temporary file is deleted best-effort and a
/// `FileSystemException` identifies the destination. Serialize concurrent
/// writes to the same destination with [AtomicWriteQueue].
Future<void> atomicWriteString(File file, String content) async {
  final tmp = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
  try {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  } catch (error) {
    await _deleteTemporaryFile(tmp);
    throw FileSystemException(
      'Failed to replace file safely: $error',
      file.path,
    );
  }
}

/// Purpose: Atomically replace [file] with [bytes] through a same-directory
/// temporary file.
/// Inputs: [file], [bytes].
/// Returns: A future completing after the destination is replaced.
/// Side effects: Creates the parent directory when needed, writes a temporary
/// file with `flush: true`, then renames it over [file].
/// Notes: On any failure, the temporary file is deleted best-effort and a
/// `FileSystemException` identifies the destination. Serialize concurrent
/// writes to the same destination with [AtomicWriteQueue].
Future<void> atomicWriteBytes(File file, List<int> bytes) async {
  final tmp = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
  try {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } catch (error) {
    await _deleteTemporaryFile(tmp);
    throw FileSystemException(
      'Failed to replace file safely: $error',
      file.path,
    );
  }
}

/// Purpose: Delete a failed write's temporary file without masking the
/// original write/rename error.
/// Inputs: [tmp].
/// Returns: A future completing after best-effort cleanup.
/// Side effects: May delete [tmp].
/// Notes: Internal helper; cleanup errors are deliberately swallowed, matching
/// the existing app implementations.
Future<void> _deleteTemporaryFile(File tmp) async {
  try {
    if (await tmp.exists()) {
      await tmp.delete();
    }
  } catch (_) {
    // Preserve the original write/rename failure.
  }
}

/// Purpose: Serialize asynchronous writes for one storage owner or file.
/// Inputs: Write operations passed to [enqueue].
/// Returns: A future per operation and an [idle] future for the queue tail.
/// Side effects: Executes queued operations in submission order.
/// Notes: Mirrors MyDay's load-bearing per-storage write-queue pattern. Each
/// caller should keep its own instance; this avoids globally serializing
/// unrelated files. A failed operation still fails its returned future, while
/// the internal tail absorbs that error so later operations continue.
class AtomicWriteQueue {
  Future<void> _tail = Future<void>.value();

  /// Purpose: Append [operation] to the queue and run it after all prior writes.
  /// Inputs: [operation].
  /// Returns: A future with this operation's own success or error.
  /// Side effects: Advances the internal queue tail and invokes [operation]
  /// exactly once.
  /// Notes: Prior operation failures do not block this operation. Callers still
  /// observe their own operation's failure through the returned future.
  Future<void> enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation(), onError: (_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }

  /// Purpose: Expose a future that completes when all currently queued writes
  /// have settled.
  /// Inputs: None.
  /// Returns: The error-absorbing internal queue tail.
  /// Side effects: None.
  /// Notes: Operations enqueued after this getter is read are not included.
  Future<void> get idle => _tail;
}
