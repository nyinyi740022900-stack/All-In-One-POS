import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import 'activate_screen.dart';
import 'invoice_list_screen.dart';
import 'invoices_web_session.dart';

/// Root of the Invoices Web companion (Phase 1 "computer" surface) — a
/// read-only, print-focused view of a shop's own invoices for a desktop
/// browser, reusing the same device-activation flow (and device-slot fee
/// model) as adding another phone. Not for checkout/inventory — that's a
/// much larger Phase 2 (needs a web-compatible local DB, USB/network
/// printing, etc.), deliberately out of scope here.
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
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6C4AB6), useMaterial3: true),
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
