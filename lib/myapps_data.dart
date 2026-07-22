/// Purpose: Public barrel for the `myapps_data` package — shared WebDAV sync and
/// data-management engines for MyAnime / MyDay / MyDevice.
/// Inputs: None (library declaration only).
/// Returns: N/A.
/// Side effects: None.
/// Notes: Exports are added as engines land (workspace PLAN.md, Phase 2):
/// storage/ (StorageAdapter, atomic I/O), json/ (preservation engine), merge/
/// (mergeRecords&lt;T&gt;), modules/ (DataModule, ModuleRegistry), webdav/ (config,
/// client, upload lock, sync engine, progress), sync/ (auto-sync scheduler, wake
/// lock), backup/ (BackupEngine), data/ (ZIP transfer). Public API goes through
/// this barrel only; consumers must not import `src/` paths directly.
library;
