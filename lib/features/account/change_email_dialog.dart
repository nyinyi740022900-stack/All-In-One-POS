import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'account_action_error.dart';
import 'account_repository.dart';

Future<bool?> showChangeEmailDialog(
  BuildContext context, {
  required Future<AccountActionResult> Function(String) submit,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ChangeEmailDialog(submit: submit),
);

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({required this.submit});
  final Future<AccountActionResult> Function(String) submit;
  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.submit(_email.text);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = accountActionErrorMessage(
        AppLocalizations.of(context),
        result.error,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.accountChangeEmail),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.accountChangeEmailHelp),
              const SizedBox(height: AppTheme.space3),
              TextField(
                controller: _email,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l.accountNewEmail,
                  errorText: _error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const ButtonSpinner() : Text(l.accountChangeEmail),
          ),
        ],
      ),
    );
  }
}
