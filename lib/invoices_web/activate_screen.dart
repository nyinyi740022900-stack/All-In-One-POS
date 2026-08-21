import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/account/auth_password_field.dart';
import '../l10n/app_localizations.dart';
import 'invoices_web_session.dart';

class _LocaleBar extends StatelessWidget implements PreferredSizeWidget {
  const _LocaleBar({required this.locale, required this.onToggle});
  final Locale locale;
  final VoidCallback onToggle;

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      elevation: 0,
      toolbarHeight: 40,
      automaticallyImplyLeading: false,
      actions: [
        TextButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.language, size: 16),
          label: Text(
            locale.languageCode == 'my' ? l.languageEnglish : l.languageMyanmar,
          ),
        ),
      ],
    );
  }
}

/// Gate for the invoices companion. Online shops sign in with the same
/// email as the phone (this computer counts as one extra device). Offline
/// shops can still paste a key. Free plan without an account is the Windows
/// POS app's Continue Free — this page cannot see local phone data.
class ActivateScreen extends StatefulWidget {
  const ActivateScreen({
    super.key,
    required this.locale,
    required this.onToggleLocale,
    required this.onActivated,
  });
  final Locale locale;
  final VoidCallback onToggleLocale;
  final VoidCallback onActivated;

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _key.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String code) => switch (code) {
    'empty_signin' => l.invWebErrorEmptySignIn,
    'empty_key' => l.invWebErrorEmptyKey,
    'wrong_password' => l.accountDeleteWrongPassword,
    'not_a_shop' => l.invWebErrorNotAShop,
    'invalid_key' => l.invWebErrorInvalidKey,
    'device_mismatch' => l.invWebErrorDeviceMismatch,
    'payment_required' => l.invWebErrorPaymentRequired,
    'network_error' => l.invWebErrorNetwork,
    'activated_refresh_pending' => l.invWebErrorRefreshPending,
    _ => l.invWebErrorActivationFailed,
  };

  Future<void> _finish(String? errorCode) async {
    if (!mounted) return;
    if (errorCode != null) {
      setState(() {
        _busy = false;
        _error = _errorMessage(AppLocalizations.of(context), errorCode);
      });
      return;
    }
    widget.onActivated();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _finish(
      await InvoicesWebSession.signIn(_email.text, _password.text),
    );
  }

  Future<void> _activateKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _finish(await InvoicesWebSession.activate(_key.text));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: _LocaleBar(locale: widget.locale, onToggle: widget.onToggleLocale),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandMark(size: 56)),
                const SizedBox(height: AppTheme.space4),
                Text(
                  l.invWebActivateTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.invWebActivateHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.invWebFreeHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
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
                  decoration: InputDecoration(labelText: l.accountEmail),
                ),
                const SizedBox(height: AppTheme.space3),
                AuthPasswordField(
                  controller: _password,
                  labelText: l.accountPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppTheme.space3),
                  InlineErrorBanner(message: _error!),
                ],
                const SizedBox(height: AppTheme.space4),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const ButtonSpinner()
                      : Text(l.accountSignIn),
                ),
                const SizedBox(height: AppTheme.space4),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l.invWebKeySection),
                  children: [
                    TextField(
                      controller: _key,
                      decoration: InputDecoration(labelText: l.invWebKeyLabel),
                      onSubmitted: (_) => _busy ? null : _activateKey(),
                    ),
                    const SizedBox(height: AppTheme.space3),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _activateKey,
                        child: Text(l.invWebActivateButton),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
