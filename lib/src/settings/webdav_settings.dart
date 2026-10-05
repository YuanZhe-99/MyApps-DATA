import 'package:flutter/material.dart';

/// Common sync actions; callers own confirmation, conflict resolution and effects.
class MyAppsWebDavSyncActions extends StatelessWidget {
  final bool syncing;
  final String syncLabel;
  final String syncingLabel;
  final String uploadLabel;
  final String downloadLabel;
  final VoidCallback onSync;
  final VoidCallback onUpload;
  final VoidCallback onDownload;

  /// Purpose: Bind manual and force sync actions without moving domain policy.
  /// Inputs: Labels, busy state and callbacks. Returns: Actions. Side effects: None.
  /// Notes: Caller confirms force operations and handles conflicts.
  const MyAppsWebDavSyncActions({
    super.key,
    required this.syncing,
    required this.syncLabel,
    required this.syncingLabel,
    required this.uploadLabel,
    required this.downloadLabel,
    required this.onSync,
    required this.onUpload,
    required this.onDownload,
  });

  /// Purpose: Render sync and force action controls.
  /// Inputs: context. Returns: Action column. Side effects: Supplied callbacks.
  /// Notes: All actions disable while sync is running.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: syncing ? null : onSync,
        icon: syncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
        label: Text(syncing ? syncingLabel : syncLabel),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: syncing ? null : onUpload,
              icon: const Icon(Icons.upload, size: 18),
              label: Text(uploadLabel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: syncing ? null : onDownload,
              icon: const Icon(Icons.download, size: 18),
              label: Text(downloadLabel),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Shared disconnect affordance with application-owned confirmation.
class MyAppsWebDavDisconnect extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// Purpose: Bind a disconnect interaction.
  /// Inputs: Label and callback. Returns: Button. Side effects: None.
  /// Notes: The caller owns confirmation and configuration removal.
  const MyAppsWebDavDisconnect({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// Purpose: Render the common disconnect button.
  /// Inputs: context. Returns: Button. Side effects: Invokes caller callback.
  /// Notes: Uses the theme's error color.
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.link_off),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

/// Save and connection-test actions with externally owned progress.
class MyAppsWebDavConnectionActions extends StatelessWidget {
  final String saveLabel;
  final String testLabel;
  final VoidCallback? onSave;
  final VoidCallback? onTest;
  final bool testing;

  /// Purpose: Bind connection actions to application operations.
  /// Inputs: Labels, callbacks and test progress. Returns: Actions.
  /// Side effects: None. Notes: Does not perform network calls.
  const MyAppsWebDavConnectionActions({
    super.key,
    required this.saveLabel,
    required this.testLabel,
    required this.onSave,
    required this.onTest,
    required this.testing,
  });

  /// Purpose: Render save/test actions and busy indication.
  /// Inputs: context. Returns: Equal-width action row.
  /// Side effects: Invokes supplied callbacks. Notes: Disables testing while busy.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton(onPressed: onSave, child: Text(saveLabel)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: OutlinedButton(
          onPressed: testing ? null : onTest,
          child: testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(testLabel),
        ),
      ),
    ],
  );
}

/// WebDAV connection editor with application-owned controllers and labels.
class MyAppsWebDavSettings extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController pathController;
  final String urlLabel;
  final String usernameLabel;
  final String passwordLabel;
  final String pathLabel;
  final String pathHint;
  final ValueChanged<String>? onUrlChanged;
  final Widget? afterUrl;

  /// Purpose: Bind connection fields without owning credentials or persistence.
  /// Inputs: Controllers, labels, remote path hint and optional endpoint content.
  /// Returns: Editor. Side effects: None.
  /// Notes: Controllers are created and disposed by the application.
  const MyAppsWebDavSettings({
    super.key,
    required this.urlController,
    required this.usernameController,
    required this.passwordController,
    required this.pathController,
    required this.urlLabel,
    required this.usernameLabel,
    required this.passwordLabel,
    required this.pathLabel,
    required this.pathHint,
    this.onUrlChanged,
    this.afterUrl,
  });

  /// Purpose: Render consistent WebDAV fields with optional application content.
  /// Inputs: context. Returns: Fields. Side effects: Edits supplied controllers.
  /// Notes: No network or storage calls; passwords stay obscured.
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: urlController,
        decoration: InputDecoration(
          labelText: urlLabel,
          hintText: 'https://example.com/remote.php/dav/files/user',
        ),
        keyboardType: TextInputType.url,
        onChanged: onUrlChanged,
      ),
      if (afterUrl != null) ...[const SizedBox(height: 16), afterUrl!],
      const SizedBox(height: 12),
      TextField(
        controller: usernameController,
        decoration: InputDecoration(labelText: usernameLabel),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: passwordController,
        decoration: InputDecoration(labelText: passwordLabel),
        obscureText: true,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: pathController,
        decoration: InputDecoration(labelText: pathLabel, hintText: pathHint),
      ),
    ],
  );
}

/// Shared automatic-sync preference; application callback owns its effects.
class MyAppsWebDavAutoSync extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Purpose: Bind the automatic-sync preference.
  /// Inputs: Text, value and callback. Returns: Control. Side effects: None.
  /// Notes: Does not save configuration or schedule synchronization.
  const MyAppsWebDavAutoSync({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  /// Purpose: Render the common automatic-sync control.
  /// Inputs: context. Returns: Switch tile. Side effects: Forwards changes.
  /// Notes: Inherits application theme.
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(description),
    value: value,
    onChanged: onChanged,
  );
}
