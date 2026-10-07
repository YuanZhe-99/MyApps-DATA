# lib/src/secrets/secret_store.dart

One application's local secrets file in its active app directory. The application injects the file
name and the key namespaces it owns. The file is never in a `ModuleRegistry`, so the sync, backup
and ZIP engines never read it.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `SecretsUnreadableException` | class | A | Typed I/O failure reading the file; extends `FileSystemException`. |
| `SecretsUnreadableException(...)` | constructor | A | Creates the exception with message, path and OS error. |
| `SecretStore` | class | A | Namespaced access to one secrets file. |
| `SecretStore(...)` | constructor | A | Binds storage, file name, namespaces, `onSaved` and clock; validates them. |
| `_lock` | private getter | A | The in-app lock shared by every store over the same file name. |
| `ownsId` | method | A | True for `<namespace>:<rest>` with a declared namespace. |
| `_checkId` | private method | A | Throws `ArgumentError` for a foreign id. |
| `file` | method | A | Resolves the file in the active app directory per call. |
| `load` | method | A | Tolerant read for display or requests; empty on any problem. |
| `loadForWrite` | method | A | Strict read for a write; sets bad content aside, throws on I/O errors. |
| `_setAside` | private method | A | Renames bad content to `<fileName>.unreadable-<UTC timestamp>`. |
| `withLock` | method | A | Runs a read-modify-write without interleaving. |
| `save` | method | A | Atomic write, then `onSaved`. |
| `saveQuiet` | method | A | Atomic write without `onSaved`. |
| `keyFor` | method | A | One owned id's key, read from disk each time. |
| `setKey` | method | A | Sets or clears (tombstone) one owned id's key under the lock. |
| `configuredIds` | method | A | Owned ids holding a usable key. |
| `deleteAll` | method | A | Deletes the file under the lock, leaving no tombstones. |

Eighteen declarations.

## Namespaces

An id belongs to namespace `ns` when it is `ns:<rest>` with a non-empty rest. `keyFor` and `setKey`
reject foreign ids, and `configuredIds` omits them. Namespaces restrict the API, not the file:
entries in other namespaces are preserved on every write and still travel in an exchange. Use a
distinct file name per application to keep applications' files apart.

## Reading and failure handling

| Situation | `load` | `loadForWrite` |
|---|---|---|
| Missing or blank file | empty | empty |
| Not UTF-8, not JSON, or not a JSON object | empty | renamed aside, then empty |
| I/O error, or a non-file at the path | empty | `SecretsUnreadableException`, nothing changed |
| Rename of bad content fails | — | `SecretsUnreadableException` |

The aside timestamp is the UTC ISO-8601 time with `-`, `:` and `.` removed, for example
`transcribe_secrets.json.unreadable-20261006T101500123456Z`, matching MyTranscribe.

## Lock

`withLock` serializes actions on an `AtomicWriteQueue` keyed by file name, shared by every
`SecretStore` instance over that name in the process. It is not re-entrant: never call `withLock`,
`setKey` or `deleteAll` from inside an action, and never make a network call while it is held.
