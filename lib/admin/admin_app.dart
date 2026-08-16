import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import 'admin_api.dart';
import 'admin_dashboard_screen.dart';
import 'admin_login_screen.dart';

/// The vendor's own internal tool (license/key management for shops running
/// All In One POS), not customer-facing storefront chrome — so unlike the
/// storefront-web design question, there's no reason for this to diverge
/// visually from the rest of the product. It shares [AppTheme]/[AppColors]
/// wholesale rather than growing its own palette: before this it ran a raw
/// `ColorScheme.fromSeed(seedColor: Color(0xFF00695C))` (a teal with no
/// relationship to the app's actual `#0F5C3E` brand green) and no
/// `textTheme` at all — the exact "beginner tell #1" from the design-pass
/// rubric. `AppTheme`/`AppColors` are pure `package:flutter/material.dart` +
/// internal l10n, so nothing here breaks the Flutter Web build.
///
/// This console is deliberately **English-only** (every string in
/// `admin/*` is a literal, there is no `AppLocalizations` import anywhere in
/// this directory) — `localeCode: 'en'` is passed explicitly so Myanmar is
/// only ever a font *fallback* here, never the primary family, and no
/// `localizationsDelegates`/`supportedLocales` are added (that would pull in
/// a translation pipeline this screen was never part of).
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'All In One POS Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(localeCode: 'en'),
      darkTheme: AppTheme.dark(localeCode: 'en'),
      home: const _AuthGate(),
    );
  }
}

/// Routes between login and dashboard based on the Supabase auth session, and
/// blocks non-admin accounts.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _api = AdminApi();

  @override
  Widget build(BuildContext context) {
    if (!Env.hasBackend) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No backend configured. Run with '
              '--dart-define-from-file=env.local.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        if (!_api.isSignedIn) {
          return AdminLoginScreen(api: _api, onSignedIn: _refresh);
        }
        if (!_api.isAdmin) {
          return _NotAuthorized(api: _api, onSignedOut: _refresh);
        }
        return AdminDashboardScreen(api: _api, onSignedOut: _refresh);
      },
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }
}

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized({required this.api, required this.onSignedOut});
  final AdminApi api;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyStateView(
        icon: Icons.block,
        title: 'This account is not an admin.',
        message: 'Sign in with an account that has admin access to '
            'All In One POS licensing.',
        actionLabel: 'Sign out',
        onAction: () async {
          await api.signOut();
          onSignedOut();
        },
      ),
    );
  }
}
