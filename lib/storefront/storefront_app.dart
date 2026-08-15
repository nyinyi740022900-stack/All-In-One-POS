import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'storefront_page.dart';

/// Public storefront web app. The shop is chosen by the URL:
///   `https://host/slug`         (path)   e.g. /aungset-3f9a
///   `https://host/?shop=slug`   (query)  fallback for local dev
class StorefrontApp extends StatefulWidget {
  const StorefrontApp({super.key});

  @override
  State<StorefrontApp> createState() => _StorefrontAppState();
}

class _StorefrontAppState extends State<StorefrontApp> {
  // Myanmar-first, matching the main app's default and this page's audience.
  // Anonymous customers have no account/settings to persist a choice in, so
  // this is plain in-memory state threaded down via a toggle button — see
  // StorefrontLocaleBar.
  Locale _locale = const Locale('my');

  String get _slug {
    final uri = Uri.base;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.queryParameters['shop'] ?? '';
  }

  void _toggleLocale() => setState(() {
        _locale =
            _locale.languageCode == 'my' ? const Locale('en') : const Locale('my');
      });

  @override
  Widget build(BuildContext context) {
    final slug = _slug;
    return MaterialApp(
      title: 'Shop',
      debugShowCheckedModeBanner: false,
      // Same design system as the rest of GoldPOSMM (`AppTheme`), not a
      // bespoke palette for this page. This page has no per-shop branding to
      // apply (no shop-specific colour field exists anywhere in the data
      // model — grep-confirmed) and no comment anywhere suggested the old
      // untouched `colorSchemeSeed: Color(0xFF6C4AB6)` was a deliberate
      // choice; it reads as the framework default nobody replaced. Reusing
      // `AppTheme` here is a real functional win, not just consistency for
      // its own sake: it gets this page the tuned type scale (in particular
      // the taller line-heights `AppTheme` adds for Myanmar diacritics —
      // this storefront defaults to `my` and previously had zero line-height
      // tuning of its own), the radius/elevation/motion tokens, and
      // `AppColors`' soft-fill tier for free, applied automatically to every
      // `Card`/`FilledButton`/bottom sheet already in this file via
      // `ThemeData`, without hand-rolling a second design system for one
      // extra Flutter Web target. Deliberately light-only, matching this
      // page's behaviour before this change (no `darkTheme:` was set either).
      theme: AppTheme.light(localeCode: _locale.languageCode),
      locale: _locale,
      // Force the chosen locale — never fall back to the visitor's browser
      // locale (same rule the main app follows).
      localeResolutionCallback: (_, _) => _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: slug.isEmpty
          ? _NoSlug(locale: _locale, onToggleLocale: _toggleLocale)
          : StorefrontPage(
              slug: slug, locale: _locale, onToggleLocale: _toggleLocale),
    );
  }
}

class _NoSlug extends StatelessWidget {
  const _NoSlug({required this.locale, required this.onToggleLocale});
  final Locale locale;
  final VoidCallback onToggleLocale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: StorefrontLocaleBar(locale: locale, onToggle: onToggleLocale),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space5),
          child: Text(l.storefrontOpenShopLink, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
