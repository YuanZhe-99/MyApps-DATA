import 'package:flutter/material.dart';

import '../webdav/endpoint_security.dart';

/// One entry in the application-supplied data inventory.
class MyAppsWebDavPrivacyItem {
  /// Localized entry title, such as a data module name.
  final String title;

  /// Optional localized description of what the entry contains.
  final String? description;

  /// Purpose: Describe one uploaded data module or optional content item.
  /// Inputs: Localized [title] and optional [description].
  /// Returns: An immutable item. Side effects: None.
  /// Notes: Applications derive items from their own registry and settings.
  const MyAppsWebDavPrivacyItem({required this.title, this.description});
}

/// Localized text for the WebDAV privacy notice.
class MyAppsWebDavPrivacyNoticeLabels {
  final String title;
  final String intro;
  final String modulesHeading;
  final String optionalContentHeading;
  final String destinationHeading;
  final String encryptionHeading;
  final String transportHeading;
  final String Function(EndpointVerdict verdict) transportDescription;
  final String insecureHttpWarning;
  final String? noThirdPartiesStatement;
  final String confirmLabel;
  final String declineLabel;

  /// Purpose: Bundle every user-visible string the notice renders.
  /// Inputs: Headings, intro, a verdict describer, the insecure-HTTP warning,
  /// an optional no-third-parties statement and action labels.
  /// Returns: Labels. Side effects: None.
  /// Notes: The package ships no localized strings; [transportDescription]
  /// receives the full verdict so applications can name the reason.
  const MyAppsWebDavPrivacyNoticeLabels({
    required this.title,
    required this.intro,
    required this.modulesHeading,
    required this.optionalContentHeading,
    required this.destinationHeading,
    required this.encryptionHeading,
    required this.transportHeading,
    required this.transportDescription,
    required this.insecureHttpWarning,
    this.noThirdPartiesStatement,
    required this.confirmLabel,
    required this.declineLabel,
  });
}

/// Body of the WebDAV privacy notice: inventory, destination and transport.
class MyAppsWebDavPrivacyNotice extends StatelessWidget {
  final MyAppsWebDavPrivacyNoticeLabels labels;
  final List<MyAppsWebDavPrivacyItem> modules;
  final List<MyAppsWebDavPrivacyItem> optionalContent;
  final String destinationHost;
  final String encryptionStatement;
  final EndpointVerdict verdict;

  /// Purpose: Bind the notice content to application-supplied facts.
  /// Inputs: [labels], uploaded [modules], [optionalContent], the
  /// [destinationHost], the [encryptionStatement] and the endpoint [verdict].
  /// Returns: Notice content. Side effects: None.
  /// Notes: Performs no network or storage calls; the caller evaluates the
  /// verdict with [evaluateEndpointSecurity].
  const MyAppsWebDavPrivacyNotice({
    super.key,
    required this.labels,
    required this.modules,
    this.optionalContent = const [],
    required this.destinationHost,
    required this.encryptionStatement,
    required this.verdict,
  });

  /// Purpose: Render the notice sections in a scrollable column.
  /// Inputs: context. Returns: Content. Side effects: None.
  /// Notes: Insecure HTTP adds an error-colored warning.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insecure = verdict.security == EndpointSecurity.insecureHttp;
    final secure = verdict.allowed;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    Widget items(List<MyAppsWebDavPrivacyItem> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(item.title),
            subtitle: item.description == null ? null : Text(item.description!),
          ),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(labels.intro),
          heading(labels.modulesHeading),
          items(modules),
          if (optionalContent.isNotEmpty) ...[
            heading(labels.optionalContentHeading),
            items(optionalContent),
          ],
          heading(labels.destinationHeading),
          SelectableText(destinationHost),
          if (labels.noThirdPartiesStatement != null) ...[
            const SizedBox(height: 4),
            Text(labels.noThirdPartiesStatement!),
          ],
          heading(labels.encryptionHeading),
          Text(encryptionStatement),
          heading(labels.transportHeading),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                secure ? Icons.lock_outline : Icons.lock_open,
                color: secure ? null : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(labels.transportDescription(verdict))),
            ],
          ),
          if (insecure) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        labels.insecureHttpWarning,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Purpose: Show the privacy notice and wait for the user's decision.
/// Inputs: [context] and the same facts as [MyAppsWebDavPrivacyNotice].
/// Returns: True only when the user confirms; false on decline or dismissal.
/// Side effects: Shows a modal dialog.
/// Notes: Callers persist the acknowledgement and enable sync only on true;
/// on false they store nothing and make no request.
Future<bool> showMyAppsWebDavPrivacyNotice(
  BuildContext context, {
  required MyAppsWebDavPrivacyNoticeLabels labels,
  required List<MyAppsWebDavPrivacyItem> modules,
  List<MyAppsWebDavPrivacyItem> optionalContent = const [],
  required String destinationHost,
  required String encryptionStatement,
  required EndpointVerdict verdict,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(labels.title),
      content: SizedBox(
        width: 480,
        child: MyAppsWebDavPrivacyNotice(
          labels: labels,
          modules: modules,
          optionalContent: optionalContent,
          destinationHost: destinationHost,
          encryptionStatement: encryptionStatement,
          verdict: verdict,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(labels.declineLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(labels.confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Visible indicator that sync is paused until the notice is reviewed.
class MyAppsWebDavSyncPausedBanner extends StatelessWidget {
  final String message;
  final String reviewLabel;
  final VoidCallback? onReview;

  /// Purpose: Bind the paused-sync message and review action.
  /// Inputs: Localized [message], [reviewLabel] and [onReview].
  /// Returns: Banner tile. Side effects: None.
  /// Notes: The application decides when to show it, typically for
  /// [WebDavPrivacyStatus.syncPaused].
  const MyAppsWebDavSyncPausedBanner({
    super.key,
    required this.message,
    required this.reviewLabel,
    required this.onReview,
  });

  /// Purpose: Render the paused state with a review button.
  /// Inputs: context. Returns: Tile. Side effects: Invokes [onReview].
  /// Notes: Uses the theme's tertiary container colors.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.pause_circle_outline,
          color: scheme.onTertiaryContainer,
        ),
        title: Text(
          message,
          style: TextStyle(color: scheme.onTertiaryContainer),
        ),
        trailing: TextButton(onPressed: onReview, child: Text(reviewLabel)),
      ),
    );
  }
}
