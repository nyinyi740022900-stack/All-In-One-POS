import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/db_encryption.dart';
import '../../l10n/app_localizations.dart';
import '../support/viber_launch.dart';

/// Shown instead of the app when the device's database files are encrypted
/// and their key can't be read ([DbKeyUnavailableException]). It runs with no
/// database at all — no providers, no settings — so the language follows the
/// phone and the support number comes from the backend when online.
///
/// Nothing here deletes data. "Start with an empty shop" moves the locked
/// files into a folder beside them; Restore from a backup file or a Premium
/// re-sync then brings the shop back.
class DbLockedApp extends StatelessWidget {
  const DbLockedApp({
    super.key,
    required this.error,
    required this.documentsDir,
    required this.onUnlocked,
  });

  final DbKeyUnavailableException error;
  final String documentsDir;

  /// Re-runs the normal startup; throws [DbKeyUnavailableException] again
  /// when the files are still locked.
  final Future<void> Function() onUnlocked;

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDispatcher.instance.locale.languageCode;
    final locale = Locale(phone == 'my' ? 'my' : 'en');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(localeCode: locale.languageCode),
      darkTheme: AppTheme.dark(localeCode: locale.languageCode),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DbLockedScreen(
        error: error,
        documentsDir: documentsDir,
        onUnlocked: onUnlocked,
      ),
    );
  }
}

class DbLockedScreen extends StatefulWidget {
  const DbLockedScreen({
    super.key,
    required this.error,
    required this.documentsDir,
    required this.onUnlocked,
    this.loadSupportNumber = _supportNumberFromBackend,
  });

  final DbKeyUnavailableException error;
  final String documentsDir;
  final Future<void> Function() onUnlocked;
  final Future<String?> Function() loadSupportNumber;

  @override
  State<DbLockedScreen> createState() => _DbLockedScreenState();
}

class _DbLockedScreenState extends State<DbLockedScreen> {
  bool _busy = false;
  String? _support;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.loadSupportNumber().then((n) {
        if (mounted && n != null && n.isNotEmpty) setState(() => _support = n);
      }),
    );
  }

  Future<void> _retry() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.onUnlocked();
    } on DbKeyUnavailableException {
      messenger.showSnackBar(SnackBar(content: Text(l.dbLockedStillLocked)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startEmpty() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dbLockedStartEmptyTitle),
        content: Text(l.dbLockedStartEmptyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.dbLockedStartEmptyConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await DbEncryption.setAsideLockedFiles(widget.documentsDir);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
      return;
    }
    if (!mounted) return;
    await _retry();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hint = widget.error.reason == DbLockReason.keyUnreadable
        ? l.dbLockedUnreadableHint
        : l.dbLockedMissingHint;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    l.dbLockedTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.space3),
                  Text(l.dbLockedBody, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppTheme.space2),
                  Text(hint, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppTheme.space5),
                  FilledButton.icon(
                    onPressed: _busy ? null : _retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.dbLockedRetry),
                  ),
                  if (_support != null) ...[
                    const SizedBox(height: AppTheme.space2),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => openSupportViber(context, number: _support!),
                      icon: const Icon(Icons.support_agent),
                      label: Text(l.dbLockedSupport),
                    ),
                  ],
                  const SizedBox(height: AppTheme.space5),
                  TextButton(
                    onPressed: _busy ? null : _startEmpty,
                    child: Text(l.dbLockedStartEmpty),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The support Viber number, straight from `app_config` (the cached copy
/// lives in the locked database). Null offline or without a backend.
Future<String?> _supportNumberFromBackend() async {
  if (!Env.hasBackend) return null;
  try {
    final row = await Supabase.instance.client
        .from('app_config')
        .select('value')
        .eq('key', 'support.viber')
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    return row?['value'] as String?;
  } catch (_) {
    return null;
  }
}
