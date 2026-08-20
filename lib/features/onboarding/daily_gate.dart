import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/auth_password_field.dart';
import '../account/saved_login_store.dart';
import '../account/branch_providers.dart';
import '../account/branch_repository.dart';
import '../account/password_strength.dart';
import '../cash/cash_providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import 'operating_mode_providers.dart';

/// Runs once per local calendar day, for every shop regardless of plan or
/// connectivity — identity confirm (local staff PIN, or an optional account
/// sign-in) → role → branch → opening amount or Skip — then the tab shell.
class DailyGate extends ConsumerStatefulWidget {
  const DailyGate({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<DailyGate> createState() => _DailyGateState();
}

String _authErrorMessage(AppLocalizations l, String? code) => switch (code) {
  'email_taken' => l.accountEmailTaken,
  'no_backend' => l.accountNoBackend,
  'not_activated' => l.accountNotActivated,
  'pending_sync' => l.accountPendingSync,
  'stuck_outbox' => l.branchesSwitchBlockedStuckOutbox,
  'trial_already_used' => l.accountTrialAlreadyUsed,
  _ => l.accountActionFailed,
};

class _DailyGateState extends ConsumerState<DailyGate> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _shopName = TextEditingController();
  final _opening = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _register = false;
  bool _justRegistered = false;
  late final SavedLoginBinder _savedLogin;

  @override
  void initState() {
    super.initState();
    _savedLogin = SavedLoginBinder(email: _email, password: _password)
      ..attach();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _savedLogin.load(ref.read(savedLoginStoreProvider));
    });
  }

  @override
  void dispose() {
    _savedLogin.detach();
    _email.dispose();
    _password.dispose();
    _shopName.dispose();
    _opening.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  bool get _signedIn {
    try {
      return ref.read(accountRepositoryProvider).isSignedInWithRealAccount;
    } catch (_) {
      return false;
    }
  }

  /// Guarded the same way as [_signedIn]: with the gate now universal, this
  /// step renders for every shop (including ones with Supabase never
  /// initialized, e.g. widget tests), not just previously-online-only ones.
  String? get _accountEmail {
    try {
      return ref.read(accountRepositoryProvider).currentAccountEmail;
    } catch (_) {
      return null;
    }
  }

  Future<void> _finish({required bool skippedOpen}) async {
    final shopId = ref.read(shopIdProvider);
    await ref
        .read(settingsRepositoryProvider)
        .markDailyGateComplete(
          shopId,
          ymd: localCalendarYmd(),
          skippedOpen: skippedOpen,
        );
    ref.invalidate(dailyGateNeededProvider);
    widget.onDone();
  }

  /// Local, fully-offline identity confirm — reuses the same PIN machinery
  /// as the Settings > Staff mode switcher, so a shop with no connectivity
  /// (or no real account at all, e.g. Free plan) can still confirm who's
  /// opening the shop today.
  Future<void> _continueAsRole(String target) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await switchStaffRole(context, ref, target);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) setState(() => _step = 1);
  }

  Future<void> _auth() async {
    final l = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    final registering =
        _register && ref.read(staffRoleProvider).valueOrNull != 'staff';
    if (registering && _shopName.text.trim().isEmpty) return;
    if (registering && _password.text != _confirmPassword.text) {
      setState(() {
        _busy = false;
        _error = l.accountPasswordMismatch;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (registering) {
      final result = await ref
          .read(accountRepositoryProvider)
          .signupShop(
            _shopName.text.trim(),
            _email.text.trim(),
            _password.text,
          );
      if (!mounted) return;
      if (result.ok && result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
        ref.invalidate(backendAccountRoleProvider);
        ref.invalidate(hasRealAccountSessionProvider);
        ref.read(syncControllerProvider.notifier).sync();
        await _savedLogin.remember(
          ref.read(savedLoginStoreProvider),
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _busy = false;
          _justRegistered = true;
          _step = 1;
        });
      } else {
        setState(() {
          _busy = false;
          _error = _authErrorMessage(l, result.error);
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
      result = await ref
          .read(accountRepositoryProvider)
          .confirmWipeAndClaimDevice();
      if (!mounted) return;
    }
    if (result.ok) {
      await _savedLogin.remember(
        ref.read(savedLoginStoreProvider),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
      }
      ref.read(syncControllerProvider.notifier).sync();
      ref.invalidate(backendAccountRoleProvider);
      ref.invalidate(hasRealAccountSessionProvider);
      setState(() {
        _busy = false;
        _step = 1;
      });
    } else {
      setState(() {
        _busy = false;
        _error = _authErrorMessage(l, result.error);
      });
    }
  }

  Future<void> _pickBranch(Branch branch) async {
    if (branch.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(branchRepositoryProvider)
        .switchBranch(branch.shopId);
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
    final rosterAsync = ref.watch(staffMembersProvider);
    final localRoleAsync = ref.watch(staffRoleProvider);
    // Already signed in, or a single-owner shop with no staff roster
    // configured (the common Free-plan case) → skip the identity step
    // entirely, zero added friction. After an email-staff sign-out the
    // local PIN role is persisted as staff so this must NOT skip — otherwise
    // they'd land on the details step as Owner.
    final rosterEmpty = rosterAsync.valueOrNull?.isEmpty == true;
    final localRole = localRoleAsync.valueOrNull ?? 'owner';
    final canSkipIdentity =
        _signedIn ||
        (rosterEmpty && localRoleAsync.hasValue && localRole != 'staff');
    if (_step == 0 && canSkipIdentity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == 0) setState(() => _step = 1);
      });
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandHeroPanel(
            icon: Icons.storefront_rounded,
            imageUrl: ref.watch(shopProfileProvider).asData?.value.logoUrl,
            height: 120,
            waveAmplitude: 16,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4,
                  AppTheme.space3,
                  AppTheme.space4,
                  AppTheme.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.dailyGateTitle,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.space4),
                    Expanded(child: _buildStep(l, rosterAsync)),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.space2),
                        child: InlineErrorBanner(message: _error!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    AppLocalizations l,
    AsyncValue<List<StaffMember>> rosterAsync,
  ) {
    if (_step == 0) {
      if (!_signedIn &&
          (!rosterAsync.hasValue || !ref.watch(staffRoleProvider).hasValue)) {
        // Local roster / PIN role still loading — avoid flashing the
        // sign-in form only to skip it a frame later.
        return const AppLoadingView();
      }
      return _accountStep(l, rosterAsync.valueOrNull ?? const []);
    }
    return _detailsStep(l);
  }

  Widget _accountStep(AppLocalizations l, List<StaffMember> roster) {
    final allowRegister = ref.watch(staffRoleProvider).valueOrNull != 'staff';
    final registering = _register && allowRegister;
    return SingleChildScrollView(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (roster.isNotEmpty) ...[
              Text(
                l.staffWhoAreYou,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const IconAvatar(icon: Icons.verified_user),
                title: Text(l.dailyGateContinueAsOwner),
                onTap: _busy ? null : () => _continueAsRole('owner'),
              ),
              ListTile(
                leading: const IconAvatar(icon: Icons.badge_outlined),
                title: Text(l.dailyGateContinueAsStaff),
                onTap: _busy ? null : () => _continueAsRole('staff'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      l.dailyGateOrSignIn,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l.dailyGateAccountStep,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (allowRegister) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l.onboardOnlineTabSignIn),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l.onboardOnlineTabRegister),
                  ),
                ],
                selected: {_register},
                onSelectionChanged: (s) => setState(() => _register = s.first),
              ),
              const SizedBox(height: 16),
            ],
            if (registering) ...[
              TextField(
                controller: _shopName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l.shopName,
                  prefixIcon: const AuthFieldIcon(Icons.store_outlined),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.accountEmail,
                prefixIcon: const AuthFieldIcon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            if (registering) ...[
              AuthPasswordField(
                controller: _password,
                labelText: l.accountPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
              ),
              PasswordStrengthMeter(controller: _password),
              const SizedBox(height: 12),
              AuthPasswordField(
                controller: _confirmPassword,
                labelText: l.accountConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_busy) _auth();
                },
              ),
            ] else
              AuthPasswordField(
                controller: _password,
                labelText: l.accountPassword,
                autofillHints: const [AutofillHints.password],
                helperText: l.accountPasswordRememberedHint,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_busy) _auth();
                },
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: AppTheme.authFilledButtonStyle(),
              onPressed: _busy ? null : _auth,
              child: _busy
                  ? const ButtonSpinner()
                  : Text(
                      registering
                          ? l.onboardOnlineCreateAccount
                          : l.accountSignIn,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Role + branch (if more than one) + opening amount (if Premium and no
  /// session is already open today) — all on one page, one final button.
  Widget _detailsStep(AppLocalizations l) {
    final role = ref.watch(effectiveRoleProvider);
    final email = _accountEmail;
    final isStaff = role == 'staff';
    final branchesAsync = ref.watch(branchesProvider);
    final premium = ref.watch(isPremiumProvider);
    final existingSession = ref.watch(currentCashSessionProvider).valueOrNull;
    final needsOpening = premium && existingSession == null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_justRegistered) ...[
            Container(
              padding: const EdgeInsets.all(AppTheme.space4),
              decoration: BoxDecoration(
                color: AppColors.of(context).successSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.of(context).success,
                      ),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: Text(
                          l.onboardOnlineDone,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: AppColors.of(context).success,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space1),
                  Text(
                    l.accountReadyNoEmailWait,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.of(context).success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space4),
          ],
          Text(
            l.dailyGateRoleStep,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTheme.space2),
          Card(
            child: ListTile(
              leading: IconAvatar(
                icon: isStaff ? Icons.badge_outlined : Icons.verified_user,
                tone: isStaff ? StatusTone.attention : StatusTone.positive,
              ),
              title: Text(
                isStaff ? l.dailyGateRoleStaff : l.dailyGateRoleOwner,
              ),
              subtitle: email == null ? null : Text(email),
            ),
          ),
          branchesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.space4),
              child: AppLoadingView(),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (branches) {
              if (branches.length <= 1) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    l.dailyGateBranchStep,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final b in branches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconAvatar(
                        icon: Icons.store_mall_directory_outlined,
                        tone: b.isCurrent ? StatusTone.positive : null,
                      ),
                      title: Text(
                        b.label?.isNotEmpty == true ? b.label! : b.shopId,
                      ),
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
            Text(
              l.dailyGateOpeningStep,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l.dailyGateOpeningHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
            style: AppTheme.authFilledButtonStyle(),
            onPressed: _busy
                ? null
                : needsOpening
                ? _openRegister
                : () => _finish(skippedOpen: existingSession == null),
            child: Text(
              needsOpening ? l.cashOpenRegister : l.dailyGateContinue,
            ),
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
