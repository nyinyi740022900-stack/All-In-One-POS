import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';

/// Digits Viber's `viber://chat?number=` scheme accepts: country code,
/// no `+`, no spaces. Myanmar local `09…` becomes `959…`.
String? viberChatNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('09')) digits = '95${digits.substring(1)}';
  if (digits.length < 8) return null;
  return digits;
}

Uri? viberChatUri(String raw) {
  final number = viberChatNumber(raw);
  if (number == null) return null;
  return Uri(
    scheme: 'viber',
    host: 'chat',
    queryParameters: {'number': number},
  );
}

Future<bool> launchViberChat(String rawNumber) async {
  final uri = viberChatUri(rawNumber);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens a Viber chat with [number]. If Viber isn't installed (or the
/// number can't be parsed), copies the raw number so they can paste it.
Future<void> openSupportViber(
  BuildContext context, {
  required String number,
}) async {
  final l = AppLocalizations.of(context);
  final opened = await launchViberChat(number);
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: number));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(l.supportViberOpenFailed)));
}
