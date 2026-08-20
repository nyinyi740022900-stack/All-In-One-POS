import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import 'admin_api.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
  });
  final AdminApi api;
  final VoidCallback onSignedIn;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.signIn(_email.text.trim(), _password.text);
      widget.onSignedIn();
    } catch (e) {
      setState(() => _error = 'Sign-in failed. Check your credentials.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      maxWidth: 360,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 56),
              const SizedBox(height: AppTheme.space3),
              Text(
                'All In One POS Admin',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppTheme.space5),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppTheme.space3),
              TextField(
                controller: _password,
                focusNode: _passwordFocus,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTheme.space3),
                InlineErrorBanner(message: _error!),
              ],
              const SizedBox(height: AppTheme.space4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy ? const ButtonSpinner() : const Text('Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
