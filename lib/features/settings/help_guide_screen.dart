import 'package:flutter/material.dart';

import '../../core/build_flags.dart';
import '../../core/theme/app_theme.dart';
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
      // The Settings walkthrough is the one section that describes how
      // to obtain Premium; a store build gets the variant that omits
      // the "tap Upgrade, contact Support for a key" instructions
      // (see kCommerceUiEnabled).
      (
        l.helpGuideSettingsTitle,
        kCommerceUiEnabled
            ? l.helpGuideSettingsBody
            : l.helpGuideSettingsBodyNoCommerce,
        Icons.settings,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.helpGuideTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4,
              AppTheme.space2,
              AppTheme.space4,
              AppTheme.space3,
            ),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space4,
                    0,
                    AppTheme.space4,
                    AppTheme.space4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
