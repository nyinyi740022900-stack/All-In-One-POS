import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Static, offline, bilingual walkthrough of what each of the app's six main
/// tabs does — reached from Settings > Help. No state, no backend; content
/// lives entirely in the ARB files like the rest of the app's UI text.
class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sections = [
      (l.helpGuideSellTitle, l.helpGuideSellBody, Icons.point_of_sale),
      (l.helpGuideInventoryTitle, l.helpGuideInventoryBody, Icons.inventory_2),
      (l.helpGuideOrdersTitle, l.helpGuideOrdersBody, Icons.receipt_long),
      (l.helpGuideInvoicesTitle, l.helpGuideInvoicesBody, Icons.description),
      (l.helpGuideAnalyticsTitle, l.helpGuideAnalyticsBody, Icons.bar_chart),
      (l.helpGuideSettingsTitle, l.helpGuideSettingsBody, Icons.settings),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.helpGuideTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              l.helpGuideIntro,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          for (final (title, body, icon) in sections)
            ExpansionTile(
              leading: Icon(icon),
              title: Text(title),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(body),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
