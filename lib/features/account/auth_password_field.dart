import 'package:flutter/material.dart';

/// A password `TextField` with the standard show/hide toggle — every auth
/// screen in the app (onboarding, Shop login) needs exactly this, previously
/// copy-pasted at each call site.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String labelText;
  final Iterable<String>? autofillHints;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.labelText,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
