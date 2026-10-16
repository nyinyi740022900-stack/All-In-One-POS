import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Shown INSTEAD of the app when [AppIntegrity] finds a repackaged build.
/// Runs with no database, no providers and no backend — nothing of the
/// shop's opens inside a copy we didn't sign. Language follows the phone.
class TamperedApp extends StatelessWidget {
  const TamperedApp({super.key});

  static final _officialSite = Uri.https('allinonepos.app', '/');

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDispatcher.instance.locale.languageCode;
    final locale = Locale(phone == 'my' ? 'my' : 'en');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(localeCode: locale.languageCode),
      darkTheme: AppTheme.dark(localeCode: locale.languageCode),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TamperedScreen(),
    );
  }
}

class TamperedScreen extends StatelessWidget {
  const TamperedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.gpp_bad_outlined,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    l.tamperedTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.space3),
                  Text(l.tamperedBody, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppTheme.space2),
                  Text(l.tamperedNextStep, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppTheme.space5),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      TamperedApp._officialSite,
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l.tamperedGetApp),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
