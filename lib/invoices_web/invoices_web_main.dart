import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import 'invoices_web_app.dart';

/// Separate entry point for the Invoices Web companion (Phase 1 "computer"
/// surface) — a read-only, print-focused view of a shop's own invoices for
/// a desktop browser. Activates like another phone (device-slot fee model
/// applies); NOT a full checkout/inventory POS — see InvoicesWebApp's doc
/// comment for why that's a separate, much larger Phase 2.
///   flutter run   -d chrome -t lib/invoices_web/invoices_web_main.dart --dart-define-from-file=env.local.json
///   flutter build web        -t lib/invoices_web/invoices_web_main.dart --dart-define-from-file=env.local.json
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.hasBackend) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
  runApp(const InvoicesWebApp());
}
