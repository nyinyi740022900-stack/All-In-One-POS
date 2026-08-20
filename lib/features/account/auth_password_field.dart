import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A password `TextField` with the standard show/hide toggle — every auth
/// screen in the app (onboarding, Shop login) needs exactly this, previously
/// copy-pasted at each call site. Fixed once here so every password field
/// app-wide gets a labeled (screen-reader friendly) toggle, correct
/// `textInputAction` chaining, and error styling for free.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.errorText,
    this.helperText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String labelText;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final String? helperText;
  final bool autofocus;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        helperMaxLines: 2,
        suffixIcon: Semantics(
          label: _obscure ? l.accountShowPassword : l.accountHidePassword,
          button: true,
          // Deliberately NO `tooltip:` on the IconButton. This field is used
          // inside the onboarding / password-recovery / daily-gate flows,
          // which `app.dart` returns from `MaterialApp.router`'s `builder:` —
          // that sits ABOVE the Router, so those screens have no `Overlay`
          // ancestor and a Tooltip throws "No Overlay widget found", painting
          // a red error box over the sign-up form. The `Semantics` wrapper
          // above already gives screen readers the same label, which was the
          // actual accessibility goal; a long-press tooltip adds nothing on a
          // touch-only POS device.
          child: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    );
  }
}
