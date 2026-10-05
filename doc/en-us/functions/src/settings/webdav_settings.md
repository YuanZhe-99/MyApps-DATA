# lib/src/settings/webdav_settings.dart

## Declarations

| Declaration | Responsibility |
|---|---|
| `MyAppsWebDavSettings` constructor/build | Four connection fields, obscured password, endpoint-change callback and optional endpoint content |
| `MyAppsWebDavConnectionActions` constructor/build | Save and test actions with external busy state |
| `MyAppsWebDavSyncActions` constructor/build | Manual sync and force actions with external busy state |
| `MyAppsWebDavAutoSync` constructor/build | Automatic-sync preference |
| `MyAppsWebDavDisconnect` constructor/build | Disconnect affordance |

Fifteen declarations (five classes, constructors and build methods). Applications
own controllers and their disposal, labels, default remote paths, credentials,
confirmation dialogs, conflict resolution, progress text and persistence. The
widgets perform no network or storage operations; actions only call supplied
callbacks. Optional endpoint content supports domain-specific security information.
