import 'package:flutter/material.dart';

/// Common data-management navigation and action presentation.
enum DataSettingsAction { sync, backup, export, import, storage }

/// A data setting with application-provided labels, status and interactions.
class MyAppsDataSettingsTile extends StatelessWidget {
  final DataSettingsAction action;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final bool selected;

  /// Purpose: Bind a data action without owning routes or storage.
  /// Inputs: Action, localized text, status and callback.
  /// Returns: Data settings tile. Side effects: None.
  /// Notes: Import confirmations and export pickers remain caller-owned.
  const MyAppsDataSettingsTile({
    super.key,
    required this.action,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  /// Purpose: Render consistent data settings icons and navigation affordances.
  /// Inputs: context. Returns: Tile. Side effects: Invokes supplied action.
  /// Notes: Sync, backup and storage open application routes or dialogs.
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(switch (action) {
      DataSettingsAction.sync => Icons.cloud_sync_outlined,
      DataSettingsAction.backup => Icons.backup_outlined,
      DataSettingsAction.export => Icons.upload_file_outlined,
      DataSettingsAction.import => Icons.download_outlined,
      DataSettingsAction.storage => Icons.folder_outlined,
    }),
    title: title,
    subtitle: subtitle,
    selected: selected,
    trailing: switch (action) {
      DataSettingsAction.sync ||
      DataSettingsAction.backup ||
      DataSettingsAction.storage => const Icon(Icons.chevron_right),
      _ => null,
    },
    onTap: onTap,
  );
}

/// Shared daily-backup and retention controls with injected persistence.
class MyAppsBackupSettings extends StatelessWidget {
  final String autoBackupTitle;
  final String autoBackupDescription;
  final bool autoBackup;
  final ValueChanged<bool>? onAutoBackupChanged;
  final String retentionTitle;
  final int retentionDays;
  final List<int> retentionOptions;
  final String Function(int) retentionLabel;
  final ValueChanged<int>? onRetentionChanged;

  /// Purpose: Bind backup preferences to application-owned settings.
  /// Inputs: Labels, selected values, available retention and callbacks.
  /// Returns: Backup settings. Side effects: None.
  /// Notes: Does not schedule backup or write preferences.
  const MyAppsBackupSettings({
    super.key,
    required this.autoBackupTitle,
    required this.autoBackupDescription,
    required this.autoBackup,
    required this.onAutoBackupChanged,
    required this.retentionTitle,
    required this.retentionDays,
    required this.retentionOptions,
    required this.retentionLabel,
    required this.onRetentionChanged,
  });

  /// Purpose: Render automatic backup and a full-width retention selector.
  /// Inputs: context. Returns: Controls. Side effects: Forwards changes.
  /// Notes: Uses pane width and supports long translated labels.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        secondary: const Icon(Icons.schedule_outlined),
        title: Text(autoBackupTitle),
        subtitle: Text(autoBackupDescription),
        value: autoBackup,
        onChanged: onAutoBackupChanged,
      ),
      ListTile(
        leading: const Icon(Icons.auto_delete_outlined),
        title: Text(retentionTitle),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: DropdownButtonFormField<int>(
          initialValue: retentionDays,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final days in retentionOptions)
              DropdownMenuItem(value: days, child: Text(retentionLabel(days))),
          ],
          onChanged: onRetentionChanged == null
              ? null
              : (value) {
                  if (value != null) onRetentionChanged!(value);
                },
        ),
      ),
    ],
  );
}
