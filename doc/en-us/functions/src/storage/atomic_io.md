# lib/src/storage/atomic_io.dart

Generic atomic file replacement and optional per-storage serialized write queues.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `atomicWriteString` | function | A | Atomically replace a file with UTF-8 text. |
| `atomicWriteBytes` | function | A | Atomically replace a file with bytes. |
| `_temporaryFileFor` | private function | A | Build a unique same-directory temporary path (`.tmp-<microseconds>-<seq>`). |
| `_deleteTemporaryFile` | private function | A | Clean a failed write's temporary file best-effort. |
| `AtomicWriteQueue` | class | A | Serialize writes for one storage owner or file. |
| `AtomicWriteQueue.enqueue` | method | A | Append an operation while preserving its own result. |
| `AtomicWriteQueue.idle` | getter | A | Observe completion of the currently queued tail. |

## Atomic replacement

Both writers use the same sequence:

1. Build a same-directory temporary path named `<target>.tmp-<microsecondsSinceEpoch>-<seq>`,
   where `<seq>` is a process-wide counter so two writes to one destination that start in the same
   microsecond never share a temporary file.
2. Create the destination's parent directory recursively when needed.
3. Write with `flush: true`.
4. Rename the temporary file over the destination.
5. On any failure, delete the temporary file best-effort and throw a `FileSystemException` whose
   `path` names the intended destination.

No fsync is requested because none of the source apps uses it today. Callers needing concurrent
writes to the same destination should use an `AtomicWriteQueue`.

## `AtomicWriteQueue`

Each storage owner keeps its own queue instance, so unrelated
files are not globally serialized. `enqueue` executes each operation exactly once in submission
order. A failed operation still completes its caller-facing future with that error, while the
internal queue tail absorbs the failure so later writes continue. `idle` waits for operations that
were queued before the getter was read.
