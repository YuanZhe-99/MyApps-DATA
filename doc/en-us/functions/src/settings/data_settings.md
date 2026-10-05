# lib/src/settings/data_settings.dart

## Declarations

| Declaration | Responsibility |
|---|---|
| `DataSettingsAction` | Identify sync, backup, export, import and storage actions |
| `MyAppsDataSettingsTile` constructor/build | Render action icon, title, status, selection and navigation affordance |
| `MyAppsBackupSettings` constructor/build | Render daily backup switch and full-width retention dropdown |

Applications provide localized labels, values, routes and persistence callbacks.
Builds do not call engines or write settings. User actions invoke supplied callbacks.
Restore guards, scheduling cadence and import confirmations remain unchanged.
Material widgets inherit the application's theme.
