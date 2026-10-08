import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'mmqr_preview_page.dart';
import 'renew_request_page.dart';
import 'storefront_page.dart';

/// Public storefront web app. The shop is chosen by the URL:
///   `https://host/slug`         (path)   e.g. /aungset-3f9a
///   `https://host/?shop=slug`   (query)  fallback for local dev
///   `https://host/renew`        (path, reserved) subscription-renewal
///     request form — owner-facing, not per-shop (see RenewRequestPage).
///     Collision with a real shop slug is not possible in practice:
///     `gen_storefront_slug()` (0017_storefronts.sql) always appends a
///     random suffix, so no organic slug is ever literally "renew".
class StorefrontApp extends StatefulWidget {
  const StorefrontApp({super.key});

  @override
  State<StorefrontApp> createState() => _StorefrontAppState();
}

class _StorefrontAppState extends State<StorefrontApp> {
  // Defaults to the visitor's own browser language when it's one we
  // support, falling back to Myanmar otherwise — this page's audience is
  // mostly Myanmar shop owners/customers, but it's also the one surface a
  // diaspora customer or an international owner (Lemon Squeezy region) can
  // land on, and greeting them in Myanmar first was the wrong default for
  // that audience. Read once at construction, not on every build — a
  // visitor who taps the manual toggle owns the choice from then on, and
  // re-reading the browser locale on a later rebuild would fight that.
  // Anonymous customers have no account/settings to persist a choice in, so
  // this is plain in-memory state threaded down via a toggle button — see
  // StorefrontLocaleBar.
  late Locale _locale = _initialLocale();

  Locale _initialLocale() {
    final browser = WidgetsBinding.instance.platformDispatcher.locale;
    return AppLocalizations.supportedLocales.contains(
          Locale(browser.languageCode),
        )
        ? Locale(browser.languageCode)
        : const Locale('my');
  }

  bool get _isRenewPath => _firstSegment == 'renew';

  /// MyanMyanPay's compliance review has to see the MMQR surface, and the
  /// real one is behind an owner sign-in *and* behind MMQR being configured,
  /// which does not happen until the application is approved. Reserved like
  /// `renew`, and safe for the same reason: `gen_storefront_slug()` always
  /// appends a random suffix, so no shop can own this path.
  bool get _isMmqrPreviewPath => _firstSegment == 'mmqr-preview';

  String get _firstSegment => Uri.base.pathSegments.isEmpty
      ? ''
      : Uri.base.pathSegments.first;

  String get _slug {
    final uri = Uri.base;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.queryParameters['shop'] ?? '';
  }

  void _toggleLocale() => setState(() {
    _locale = _locale.languageCode == 'my'
        ? const Locale('en')
        : const Locale('my');
  });

  @override
  Widget build(BuildContext context) {
    final slug = _slug;
    return MaterialApp(
      title: 'Shop',
      debugShowCheckedModeBanner: false,
      // Same design system as the rest of All In One POS (`AppTheme`), not a
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
      home: _isRenewPath
          ? RenewRequestPage(locale: _locale, onToggleLocale: _toggleLocale)
          : _isMmqrPreviewPath
          ? MmqrPreviewPage(locale: _locale, onToggleLocale: _toggleLocale)
          : slug.isEmpty
          ? _NoSlug(locale: _locale, onToggleLocale: _toggleLocale)
          : StorefrontPage(
              slug: slug,
              locale: _locale,
              onToggleLocale: _toggleLocale,
            ),
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
