import 'package:flutter/material.dart';

/// Localized text for the trusted-host risk warning.
class MyAppsTrustedHostWarningLabels {
  final String title;
  final String Function(String host) body;
  final String acknowledgement;
  final String confirmLabel;
  final String cancelLabel;

  /// Purpose: Bundle the strings the warning renders.
  /// Inputs: [title]; [body] naming the host and saying that keys would then
  /// travel unencrypted over any network between this device and it;
  /// [acknowledgement] checkbox text; action labels.
  /// Returns: Labels. Side effects: None.
  /// Notes: The package ships no localized strings.
  const MyAppsTrustedHostWarningLabels({
    required this.title,
    required this.body,
    required this.acknowledgement,
    required this.confirmLabel,
    required this.cancelLabel,
  });
}

/// Purpose: Warn before the user trusts a plain-HTTP host for secrets.
/// Inputs: [context], the normalised [host] and [labels].
/// Returns: True only when the user ticks the acknowledgement and confirms;
/// false on cancel or dismissal.
/// Side effects: Shows a modal dialog.
/// Notes: Hosts the policy already allows (HTTPS, private networks,
/// Tailscale, EasyTier) never need this; it is for the explicit override.
/// Callers add the host to the device-local list only on true.
Future<bool> showMyAppsTrustedHostWarning(
  BuildContext context, {
  required String host,
  required MyAppsTrustedHostWarningLabels labels,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _TrustedHostWarning(host: host, labels: labels),
    ) ??
    false;

class _TrustedHostWarning extends StatefulWidget {
  final String host;
  final MyAppsTrustedHostWarningLabels labels;

  /// Purpose: Create the dialog. Inputs: [host], [labels].
  /// Returns: Widget. Side effects: None. Notes: Internal.
  const _TrustedHostWarning({required this.host, required this.labels});

  /// Purpose: Create state. Inputs: None. Returns: State.
  /// Side effects: None. Notes: Internal.
  @override
  State<_TrustedHostWarning> createState() => _TrustedHostWarningState();
}

class _TrustedHostWarningState extends State<_TrustedHostWarning> {
  var _understood = false;

  /// Purpose: Render the warning.
  /// Inputs: context. Returns: Dialog. Side effects: None.
  /// Notes: Confirm stays disabled until the box is ticked.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = widget.labels;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(labels.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labels.body(widget.host)),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: Text(labels.acknowledgement),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(labels.cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _understood ? () => Navigator.of(context).pop(true) : null,
          child: Text(labels.confirmLabel),
        ),
      ],
    );
  }
}
