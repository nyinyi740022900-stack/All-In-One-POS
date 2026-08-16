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
              style: AppTheme.dangerFilledButtonStyle(ctx),
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
    final draft = await showDialog<_PaymentAccountDraft>(
      context: context,
      builder: (_) => _PaymentAccountEditorDialog(existing: existing),
    );
    if (draft == null || !context.mounted) return;
    await ref.read(paymentAccountRepositoryProvider).upsertAccount(
          id: existing?.id,
          name: draft.name,
          openingBalance: draft.openingBalance,
        );
    if (context.mounted) {
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
          featureName: l.paymentAccountsTitle,
          benefits: [l.paymentAccountsBenefit1, l.paymentAccountsBenefit2],
          child: const SizedBox.shrink(),
        ),
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
                      leading: const IconAvatar(
                          icon: Icons.account_balance_wallet_outlined),
                      title: Text(a.name),
                      subtitle: MoneyText(
                        balance.when(
                          data: (v) => Money(v).withSymbol(l.currencySymbol),
                          loading: () => '…',
                          error: (_, _) => '—',
                        ),
                        textAlign: TextAlign.left,
                        color: balance.when(
                          data: (v) => v < 0 ? colors.danger : null,
                          loading: () => null,
                          error: (_, _) => null,
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

class _PaymentAccountDraft {
  const _PaymentAccountDraft(this.name, this.openingBalance);
  final String name;
  final int openingBalance;
}

/// Name + opening-balance editor. A `StatefulWidget` so the two
/// `TextEditingController`s are disposed by the dialog's own lifecycle
/// instead of a `Future` that resolves on pop, before the exit animation
/// finishes — the same dispose-after-`await` crash this session fixed in
/// `checkout_sheet.dart`, `categories_screen.dart`, and `customers_screen.dart`.
class _PaymentAccountEditorDialog extends StatefulWidget {
  const _PaymentAccountEditorDialog({this.existing});

  final PaymentAccount? existing;

  @override
  State<_PaymentAccountEditorDialog> createState() =>
      _PaymentAccountEditorDialogState();
}

class _PaymentAccountEditorDialogState
    extends State<_PaymentAccountEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _opening;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _opening = TextEditingController(
      text: widget.existing == null
          ? '0'
          : '${widget.existing!.openingBalance}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _PaymentAccountDraft(name, int.tryParse(_opening.text.trim()) ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null
          ? l.paymentAccountAdd
          : l.paymentAccountEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.paymentAccountNameLabel),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                  labelText: l.paymentAccountOpeningBalanceLabel),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.commonSave)),
      ],
    );
  }
}
