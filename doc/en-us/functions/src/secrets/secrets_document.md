# lib/src/secrets/secrets_document.dart

The local API-key secrets file as a value type, its per-key merge and its canonical encoder. The
shape is the one MyTranscribe already writes to `transcribe_secrets.json`, so an existing file reads
and re-encodes byte-identically. A secrets file is never a data module.

## Declarations

| Declaration | Kind | Tier | Purpose |
|---|---|---|---|
| `secretsDocumentVersion` | constant | A | Format version written into the file (`1`). |
| `SecretEntry` | class | A | One key (or tombstone), its UTC `updatedAt` and preserved unknown fields. |
| `SecretEntry(...)` | constructor | A | Creates an entry, normalising the time to UTC. |
| `SecretEntry.hasKey` | getter | A | False for a tombstone or blank key. |
| `SecretEntry.fromJson` | factory | A | Parses an entry; a damaged timestamp becomes the epoch. |
| `SecretEntry.toJson` | method | A | Serializes an entry; a tombstone is an explicit `null`. |
| `SecretsDocument` | class | A | Entries by record id plus preserved top-level unknown fields. |
| `SecretsDocument(...)` | constructor | A | Creates an immutable document. |
| `SecretsDocument.fromJson` | factory | A | Parses a document; wrong-typed `keys` or entries read as absent. |
| `SecretsDocument.toJson` | method | A | Serializes with ids sorted. |
| `SecretsDocument.keyFor` | method | A | One id's usable key, or null. |
| `SecretsDocument.withKey` | method | A | Sets (trimmed) or clears (tombstone) one id's key. |
| `SecretsDocument.configuredIds` | getter | A | Ids holding a usable key; never key values. |
| `mergeSecretsDocuments` | function | A | Per-key last-writer-wins merge with tombstones. |
| `encodeSecretsDocument` | function | A | Pretty-printed JSON used for local writes and uploads. |

Fifteen declarations.

## File shape

```json
{
  "version": 1,
  "keys": {
    "provider:old": {
      "apiKey": null,
      "updatedAt": "2026-09-06T00:00:00.000Z"
    },
    "provider:openai": {
      "apiKey": "sk-...",
      "updatedAt": "2026-09-05T10:00:00.000Z"
    }
  }
}
```

Ids are sorted on write, so equal content always encodes to equal bytes. Unknown top-level fields
are written before `version`, and unknown entry fields before `apiKey`; with no unknown fields the
output is identical to MyTranscribe's.

## Merge rule

- Per key, the entry with the later `updatedAt` wins; a tie goes to the remote copy so every device
  converges.
- Tombstones (`apiKey: null`) take part, so a cleared key stays cleared everywhere.
- No base snapshot: each key is one independent value.
- Top-level unknown fields are unioned, local winning.
