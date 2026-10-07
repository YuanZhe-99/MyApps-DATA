# lib/src/settings/webdav_privacy_notice.dart

## Declarations

| Declaration | Responsibility |
|---|---|
| `MyAppsWebDavPrivacyItem` constructor | One data module or optional content entry: title and optional description |
| `MyAppsWebDavPrivacyNoticeLabels` constructor | Every localized string, including a verdict describer and the insecure-HTTP warning |
| `MyAppsWebDavPrivacyNotice` constructor/build | Notice body: intro, uploaded modules, optional content, destination host, optional no-third-parties statement, encryption-at-rest statement, transport security |
| `showMyAppsWebDavPrivacyNotice` | Modal dialog returning true on confirm and false on decline or dismissal |
| `MyAppsWebDavSyncPausedBanner` constructor/build | Paused-sync message with a review action |

Eleven declarations (four classes with constructors, two build methods and one function).
Applications supply the inventory from their own registry, the destination host, the
encryption statement and the `EndpointVerdict` from `evaluateEndpointSecurity`. Plain HTTP to a
public host (`insecureHttp`) adds an error-colored warning; an unsecured verdict shows an open
lock. Callers persist the acknowledgement and enable sync only when the dialog returns true;
on false they store nothing and make no request. The widgets perform no network or storage
operations.
