import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/branch_providers.dart';
import '../account/branch_repository.dart';
import '../cash/cash_providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'operating_mode_providers.dart';

/// Online-only: once per local calendar day — account → role → branch →
/// opening amount or Skip — then the tab shell.
class OnlineDailyGate extends ConsumerStatefulWidget {
  const OnlineDailyGate({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<OnlineDailyGate> createState() => _OnlineDailyGateState();
}

class _OnlineDailyGateState extends ConsumerState<OnlineDailyGate> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _shopName = TextEditingController();
  final _opening = TextEditingController();
  bool _register = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _shopName.dispose();
    _opening.dispose();
    super.dispose();
  }

  bool get _signedIn {
    try {
      return ref.read(accountRepositoryProvider).isSignedInWithRealAccount;
    } catch (_) {
      return false;
    }
  }

  Future<void> _finish({required bool skippedOpen}) async {
    final shopId = ref.read(shopIdProvider);
    await ref.read(settingsRepositoryProvider).markDailyGateComplete(
          shopId,
          ymd: localCalendarYmd(),
          skippedOpen: skippedOpen,
        );
    ref.invalidate(onlineDailyGateNeededProvider);
    widget.onDone();
  }

  Future<void> _auth() async {
    final l = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    if (_register && _shopName.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_register) {
      final result = await ref.read(accountRepositoryProvider).signupShop(
            _shopName.text.trim(),
            _email.text.trim(),
            _password.text,
          );
      if (!mounted) return;
      if (result.ok && result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
        setState(() {
          _busy = false;
          _step = 1;
        });
      } else {
        setState(() {
          _busy = false;
          _error = result.error ?? l.accountActionFailed;
        });
      }
      return;
    }

    var result = await ref
        .read(accountRepositoryProvider)
        .signInAndClaimDevice(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (result.needsWipeConfirmation) {
      setState(() => _busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.accountSignInWipeConfirmTitle),
          content: Text(l.accountSignInWipeConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.accountSignIn),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        await Supabase.instance.client.auth.signOut();
        return;
      }
      setState(() => _busy = true);
      result =
          await ref.read(accountRepositoryProvider).confirmWipeAndClaimDevice();
      if (!mounted) return;
    }
    if (result.ok) {
      if (result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
      }
      ref.read(syncControllerProvider.notifier).sync();
      setState(() {
        _busy = false;
        _step = 1;
      });
    } else {
      setState(() {
        _busy = false;
        _error = result.error ?? l.accountActionFailed;
      });
    }
  }

  Future<void> _pickBranch(Branch branch) async {
    if (branch.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await ref.read(branchRepositoryProvider).switchBranch(branch.shopId);
    if (!mounted) return;
    if (result.ok && result.license != null) {
      ref
          .read(licenseControllerProvider.notifier)
          .applyExternal(result.license!);
      ref.read(syncControllerProvider.notifier).sync();
      setState(() => _busy = false);
    } else {
      setState(() {
        _busy = false;
        _error = result.error ?? 'branch_switch_failed';
      });
    }
  }

  Future<void> _openRegister() async {
    final raw = _opening.text.trim();
    final amount = raw.isEmpty ? 0 : int.tryParse(raw.replaceAll(',', ''));
    if (amount == null || amount < 0) return;
    // Don't open a second till session if one is already open today.
    final existing = ref.read(currentCashSessionProvider).valueOrNull;
    if (existing != null) {
      await _finish(skippedOpen: false);
      return;
    }
    setState(() => _busy = true);
    final deviceId = await ref.read(deviceIdProvider.future);
    await ref
        .read(cashSessionRepositoryProvider)
        .openSession(openingAmount: amount, deviceId: deviceId);
    if (!mounted) return;
    setState(() => _busy = false);
    await _finish(skippedOpen: false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Already signed in → skip account step on first build.
    if (_step == 0 && _signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == 0) setState(() => _step = 1);
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.dailyGateTitle,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.space4),
              Expanded(child: _buildStep(l)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(AppLocalizations l) {
    return _step == 0 ? _accountStep(l) : _detailsStep(l);
  }

  Widget _accountStep(AppLocalizations l) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.dailyGateAccountStep,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: false, label: Text(l.onboardOnlineTabSignIn)),
              ButtonSegment(
                  value: true, label: Text(l.onboardOnlineTabRegister)),
            ],
            selected: {_register},
            onSelectionChanged: (s) => setState(() => _register = s.first),
          ),
          const SizedBox(height: 16),
          if (_register) ...[
            TextField(
              controller: _shopName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.shopName),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l.accountEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: l.accountPassword,
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _auth,
            child: Text(_register
                ? l.onboardOnlineCreateAccount
                : l.accountSignIn),
          ),
        ],
      ),
    );
  }

  /// Role + branch (if more than one) + opening amount (if Premium and no
  /// session is already open today) — all on one page, one final button.
  Widget _detailsStep(AppLocalizations l) {
    final role = ref.watch(backendAccountRoleProvider) ?? 'owner';
    final email = ref.watch(accountRepositoryProvider).currentAccountEmail;
    final isStaff = role == 'staff';
    final branchesAsync = ref.watch(branchesProvider);
    final premium = ref.watch(isPremiumProvider);
    final existingSession =
        ref.watch(currentCashSessionProvider).valueOrNull;
    final needsOpening = premium && existingSession == null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.dailyGateRoleStep,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                Icon(isStaff ? Icons.badge_outlined : Icons.verified_user),
            title:
                Text(isStaff ? l.dailyGateRoleStaff : l.dailyGateRoleOwner),
            subtitle: email == null ? null : Text(email),
          ),
          branchesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (branches) {
              if (branches.length <= 1) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(l.dailyGateBranchStep,
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final b in branches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(b.label?.isNotEmpty == true
                          ? b.label!
                          : b.shopId),
                      subtitle: b.isCurrent ? Text(l.branchesCurrent) : null,
                      trailing: b.isCurrent
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.chevron_right),
                      onTap: _busy ? null : () => _pickBranch(b),
                    ),
                ],
              );
            },
          ),
          if (needsOpening) ...[
            const SizedBox(height: 8),
            Text(l.dailyGateOpeningStep,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.dailyGateOpeningHint,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.cashOpeningAmount),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : needsOpening
                    ? _openRegister
                    : () => _finish(skippedOpen: existingSession == null),
            child:
                Text(needsOpening ? l.cashOpenRegister : l.dailyGateContinue),
          ),
          if (needsOpening) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _finish(skippedOpen: true),
              child: Text(l.dailyGateSkipOpening),
            ),
          ],
        ],
      ),
    );
  }
}
