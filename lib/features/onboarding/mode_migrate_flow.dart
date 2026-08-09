import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../license/license_providers.dart';
import 'operating_mode_providers.dart';

/// One-time lock for installs that finished legacy onboarding before
/// permanent Online/Offline mode existed.
class ModeMigrateFlow extends ConsumerStatefulWidget {
  const ModeMigrateFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<ModeMigrateFlow> createState() => _ModeMigrateFlowState();
}

class _ModeMigrateFlowState extends ConsumerState<ModeMigrateFlow> {
  bool _acked = false;
  bool _busy = false;
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = SettingsRepository.operatingModeOffline;
    // Defer suggestion until after first frame so [ref] is safe to read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selected = _suggestMode());
    });
  }

  String _suggestMode() {
    final tier =
        ref.read(licenseControllerProvider).license?.tier ?? 'offline';
    if (tier == SettingsRepository.operatingModeOnline) {
      return SettingsRepository.operatingModeOnline;
    }
    try {
      final account = ref.read(accountRepositoryProvider);
      if (account.isSignedInWithRealAccount) {
        return SettingsRepository.operatingModeOnline;
      }
    } catch (_) {}
    return SettingsRepository.operatingModeOffline;
  }

  Future<void> _confirm() async {
    if (!_acked || _busy) return;
    setState(() => _busy = true);
    await lockOperatingMode(ref, _selected);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final suggestOnline =
        _suggestMode() == SettingsRepository.operatingModeOnline;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.modeMigrateTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                l.modeMigrateBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                suggestOnline
                    ? l.modeMigrateSuggestOnline
                    : l.modeMigrateSuggestOffline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              Text(l.onboardModeOnlineBullets,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(l.onboardModeOfflineBullets,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  _selected == SettingsRepository.operatingModeOnline
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(l.operatingModeOnline),
                onTap: _busy
                    ? null
                    : () => setState(() =>
                        _selected = SettingsRepository.operatingModeOnline),
              ),
              ListTile(
                leading: Icon(
                  _selected == SettingsRepository.operatingModeOffline
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(l.operatingModeOffline),
                onTap: _busy
                    ? null
                    : () => setState(() =>
                        _selected = SettingsRepository.operatingModeOffline),
              ),
              CheckboxListTile(
                value: _acked,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _acked = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(l.onboardModeAckLabel),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (_acked && !_busy) ? _confirm : null,
                child: Text(l.modeMigrateConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
