# lib/src/settings/trusted_host_warning.dart

## Declarations

| Declaration | Responsibility |
|---|---|
| `MyAppsTrustedHostWarningLabels` constructor | Title, body naming the host, acknowledgement checkbox text and action labels |
| `showMyAppsTrustedHostWarning` | Modal risk warning returning true only after the acknowledgement is ticked and confirmed |
| `_TrustedHostWarning` constructor/createState | Dialog widget for one host |
| `_TrustedHostWarningState` build | Body, acknowledgement checkbox, cancel and error-colored confirm buttons |

Eight declarations (three classes, two constructors, one createState, one build method and one
function). Endpoints the policy already allows (HTTPS, private networks, Tailscale `*.ts.net`,
EasyTier `*.et.net`) never need it; it guards the explicit override that lets secrets reach a
plain-HTTP public host. Confirm stays disabled until the box is ticked; cancel or dismissal
returns false. Callers validate the entry with `normalizeTrustedHostEntry` first and add it to the
device-local trusted list only on true.
