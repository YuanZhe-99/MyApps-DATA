# MyApps-DATA Documentation (English)

This is the English documentation tree for the `myapps_data` package. The Simplified Chinese
mirror (`doc/zh-cn/`) is a follow-up phase and does not exist yet as of this documentation pass —
see [translation-guide.md](translation-guide.md) for how it will be produced once it lands.

## Contents

- [architecture.md](architecture.md) — what this package is, its target shape, and how the three
  sibling apps (MyAnime, MyDay, MyDevice) will consume it.
- [translation-guide.md](translation-guide.md) — the English-to-Chinese translation guide and
  terminology glossary shared, byte-identical, across all four repos.
- [functions/INDEX.md](functions/INDEX.md) — the function index: every declaration currently in
  `lib/`, with links to full documentation where applicable.

## Current status

As of this writing, Phase 2 package implementation (P2.1-P2.10) is complete (see the
workspace-root `PLAN.md` and this repo's own [AGENTS.md](../../AGENTS.md)). The public barrel exports
the shared storage, preservation, merge, WebDAV, sync, backup, and ZIP engines documented under
`functions/`. Focused unit tests and 36 package-owned golden fixtures cover the shared behavior and
the synthetic MyAnime/MyDay/MyDevice registry shapes in CI. The planned pre-integration `v0.9.0`
tag/push remains a separate release gate before Phase 3 app integration. Each new source area must
gain a `doc/en-us/functions/` page and a Chinese translation in the same change set once
`doc/zh-cn/` exists.
