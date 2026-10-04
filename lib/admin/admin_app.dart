import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../l10n/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import 'admin_api.dart';
import 'admin_dashboard_screen.dart';
import 'admin_login_screen.dart';

/// Vendor administration for shop subscriptions, payments and accounts.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'All In One POS Admin',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
        message:
            'Sign in with an account that has admin access to '
            'All In One POS licensing.',
        actionLabel: 'Sign out',
        onAction: () async {
          try {
            await api.signOut();
            onSignedOut();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
            }
          }
        },
      ),
    );
  }
}
