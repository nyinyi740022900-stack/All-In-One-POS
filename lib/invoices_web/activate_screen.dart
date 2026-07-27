import 'package:flutter/material.dart';

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
              locale.languageCode == 'my' ? l.languageEnglish : l.languageMyanmar),
        ),
      ],
    );
  }
}

/// Enter a device key (generated on the phone's Settings > License > Add
/// device) to bind this browser to the shop — the same activation flow as
/// adding another phone, consuming a device slot the same way.
class ActivateScreen extends StatefulWidget {
  const ActivateScreen(
      {super.key,
      required this.locale,
      required this.onToggleLocale,
      required this.onActivated});
  final Locale locale;
  final VoidCallback onToggleLocale;
  final VoidCallback onActivated;

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String code) => switch (code) {
        'empty_key' => l.invWebErrorEmptyKey,
        'invalid_key' => l.invWebErrorInvalidKey,
        'device_mismatch' => l.invWebErrorDeviceMismatch,
        'payment_required' => l.invWebErrorPaymentRequired,
        'network_error' => l.invWebErrorNetwork,
        _ => l.invWebErrorActivationFailed,
      };

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = AppLocalizations.of(context);
    final errorCode = await InvoicesWebSession.activate(_key.text);
    if (!mounted) return;
    if (errorCode != null) {
      setState(() {
        _busy = false;
        _error = _errorMessage(l, errorCode);
      });
      return;
    }
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: _LocaleBar(locale: widget.locale, onToggle: widget.onToggleLocale),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.receipt_long,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(l.invWebActivateTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(l.invWebActivateHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _key,
                  decoration: InputDecoration(
                    labelText: l.invWebKeyLabel,
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _busy ? null : _activate(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _activate,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.invWebActivateButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
