import 'package:flutter/material.dart';

import '../../core/build_flags.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Static, offline, bilingual walkthrough of the app, in the order the tabs
/// and sub-tabs appear — reached from Shop > Help. No state, no backend;
/// content lives entirely in the ARB files like the rest of the app's UI text.
class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sections = [
      (l.helpGuideSellTitle, l.helpGuideSellBody, Icons.point_of_sale),
      (l.helpGuideInventoryTitle, l.helpGuideInventoryBody, Icons.inventory_2),
      // The Orders tab's two sub-tabs, in its order: Invoices, then Social
      // Orders.
      (l.helpGuideInvoicesTitle, l.helpGuideInvoicesBody, Icons.description),
      (l.helpGuideOrdersTitle, l.helpGuideOrdersBody, Icons.receipt_long),
      (l.helpGuideAnalyticsTitle, l.helpGuideAnalyticsBody, Icons.bar_chart),
      // The Shop tab, split the way the screen is: its Daily rows first,
      // then setup and device settings.
      (l.helpGuideDailyTitle, l.helpGuideDailyBody, Icons.today),
      // The Shop walkthrough is the one section that says where to pay for
      // Premium; a store build gets the variant that doesn't (see
      // kCommerceUiEnabled).
      (
        l.helpGuideSettingsTitle,
        kCommerceUiEnabled
            ? l.helpGuideSettingsBody
            : l.helpGuideSettingsBodyNoCommerce,
        Icons.storefront,
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
