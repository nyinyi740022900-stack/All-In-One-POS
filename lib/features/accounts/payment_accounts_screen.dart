import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'payment_account_providers.dart';

/// Payment-account directory: browse/add/edit/delete the shop's named money
/// accounts (KBZPay, WavePay, or any custom one) and see each one's running
/// balance. Cash stays a separate, untouched concept (Cash Register). See
/// `PaymentAccountRepository`.
class PaymentAccountsScreen extends ConsumerWidget {
  const PaymentAccountsScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, PaymentAccount a) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.paymentAccountDeleteConfirmTitle),
        content: Text(l.paymentAccountDeleteConfirmBody(a.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(paymentAccountRepositoryProvider).deleteAccount(a.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.paymentAccountDeleted)));
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [PaymentAccount? existing]) async {
    final l = AppLocalizations.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    final opening = TextEditingController(
        text: existing == null ? '0' : '${existing.openingBalance}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null
            ? l.paymentAccountAdd
            : l.paymentAccountEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: l.paymentAccountNameLabel),
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: l.paymentAccountOpeningBalanceLabel),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );
    final shouldSave = saved == true && name.text.trim().isNotEmpty;
    if (shouldSave) {
      await ref.read(paymentAccountRepositoryProvider).upsertAccount(
            id: existing?.id,
            name: name.text.trim(),
            openingBalance: int.tryParse(opening.text.trim()) ?? 0,
          );
    }
    name.dispose();
    opening.dispose();
    if (shouldSave && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.paymentAccountSaved)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.paymentAccountsTitle)),
        body: PremiumGate(
            featureName: l.paymentAccountsTitle, child: const SizedBox.shrink()),
      );
    }
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
    final loading = ref.watch(paymentAccountsProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l.paymentAccountsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.paymentAccountAdd),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
              ? EmptyStateView(
                  icon: Icons.account_balance_wallet_outlined,
                  title: l.paymentAccountsEmpty,
                  actionLabel: l.paymentAccountAdd,
                  onAction: () => _openEditor(context, ref),
                )
              : ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = accounts[i];
                    final balance = ref.watch(accountBalanceProvider(a));
                    final colors = AppColors.of(context);
                    return ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.account_balance_wallet_outlined)),
                      title: Text(a.name),
                      subtitle: Text(
                        balance.when(
                          data: (v) => Money(v).withSymbol(l.currencySymbol),
                          loading: () => '…',
                          error: (_, _) => '—',
                        ),
                        style: TextStyle(
                          color: balance.when(
                            data: (v) => v < 0 ? colors.danger : null,
                            loading: () => null,
                            error: (_, _) => null,
                          ),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, a),
                      ),
                      onTap: () => _openEditor(context, ref, a),
                    );
                  },
                ),
    );
  }
}
