import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'activate_screen.dart';
import 'invoice_list_screen.dart';
import 'invoices_web_session.dart';

/// Root of the Invoices Web companion — a read-only, print-focused view of
/// a shop's own invoices for a desktop or tablet browser. Online shops
/// sign in with the same email as the phone (no extra device slot). Offline
/// shops can paste a device key. Free plan without an account uses the
/// Windows POS app's Continue Free instead — this page has no local DB.
///
/// **This is the shop owner's own tool** (viewing their own invoices,
/// authenticated via the same device-activation flow as the mobile app) —
/// not a customer-facing page like `storefront_page.dart`, so the same
/// "does this deserve its own separate brand" question doesn't apply here;
/// it shares `AppTheme` for the same reason `admin_app.dart` does.
class InvoicesWebApp extends StatefulWidget {
  const InvoicesWebApp({super.key});

  @override
  State<InvoicesWebApp> createState() => _InvoicesWebAppState();
}

class _InvoicesWebAppState extends State<InvoicesWebApp> {
  Locale _locale = const Locale('my');

  void _toggleLocale() => setState(() {
        _locale =
            _locale.languageCode == 'my' ? const Locale('en') : const Locale('my');
      });

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final activated = InvoicesWebSession.shopId != null;
    return MaterialApp(
      title: 'Invoices',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(localeCode: _locale.languageCode),
      darkTheme: AppTheme.dark(localeCode: _locale.languageCode),
      locale: _locale,
      localeResolutionCallback: (_, _) => _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: activated
          ? InvoiceListScreen(locale: _locale, onToggleLocale: _toggleLocale)
          : ActivateScreen(
              locale: _locale,
              onToggleLocale: _toggleLocale,
              onActivated: _refresh,
            ),
    );
  }
}
