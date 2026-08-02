import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import 'cash_providers.dart';

/// Cash-drawer session: open with a declared float, watch what the drawer
/// should hold live, close with a counted amount to see the variance.
class CashSessionScreen extends ConsumerWidget {
  const CashSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(currentCashSessionProvider).valueOrNull;
    final history = ref.watch(cashSessionHistoryProvider).valueOrNull ?? const [];
    final pastSessions = history.where((s) => s.id != session?.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.cashRegisterTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          if (session == null)
            _ClosedCard(onOpen: () => _openRegister(context, ref))
          else
            _OpenCard(session: session, onClose: () => _closeRegister(context, ref, session)),
          const SizedBox(height: AppTheme.space5),
          Text(l.cashHistory, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.space2),
          if (pastSessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
              child: Text(l.cashNoHistory,
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            ...pastSessions.map((s) => _HistoryTile(session: s)),
        ],
      ),
    );
  }

  Future<void> _openRegister(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l.cashOpenRegister,
        amountLabel: l.cashOpeningAmount,
        confirmLabel: l.cashOpenRegister,
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deviceId = await ref.read(deviceIdProvider.future);
    await ref
        .read(cashSessionRepositoryProvider)
        .openSession(openingAmount: amount, deviceId: deviceId);
    messenger.showSnackBar(SnackBar(content: Text(l.cashRegisterOpenedMsg)));
  }

  Future<void> _closeRegister(
      BuildContext context, WidgetRef ref, CashSession session) async {
    final l = AppLocalizations.of(context);
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l.cashCloseRegister,
        amountLabel: l.cashClosingAmount,
        confirmLabel: l.cashCloseRegister,
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(cashSessionRepositoryProvider)
        .closeSession(session.id, closingAmount: amount);
    messenger.showSnackBar(SnackBar(content: Text(l.cashRegisterClosedMsg)));
  }
}

class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: AppTheme.space2),
                Expanded(child: Text(l.cashNoSession)),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.lock_open),
              label: Text(l.cashOpenRegister),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCard extends ConsumerWidget {
  const _OpenCard({required this.session, required this.onClose});
  final CashSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sym = l.currencySymbol;
    final expected = ref.watch(expectedCashProvider);
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, color: Colors.green),
                const SizedBox(width: AppTheme.space2),
                Text(l.cashRegisterOpen,
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            _kv(context, l.cashOpenedAt, df.format(session.openedAt)),
            _kv(context, l.cashOpeningAmount,
                Money(session.openingAmount).withSymbol(sym)),
            const Divider(height: AppTheme.space5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.cashExpectedNow,
                    style: Theme.of(context).textTheme.titleMedium),
                expected.when(
                  loading: () => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => const Text('—'),
                  data: (v) => Text(
                    Money(v ?? 0).withSymbol(sym),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            OutlinedButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.lock_outline),
              label: Text(l.cashCloseRegister),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value),
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.session});
  final CashSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sym = l.currencySymbol;
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final closing = session.closingAmount;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        closing == null ? Icons.lock_open : Icons.lock_outline,
        color: closing == null ? Colors.green : null,
      ),
      title: Text(df.format(session.openedAt)),
      subtitle: Text(
        closing == null
            ? l.cashRegisterOpen
            : '${l.cashOpeningAmount}: ${Money(session.openingAmount).withSymbol(sym)}'
                ' → ${l.cashClosingAmount}: ${Money(closing).withSymbol(sym)}',
      ),
      trailing: closing == null
          ? null
          : FutureBuilder<int>(
              // Variance is counted cash vs. what the drawer *should* hold
              // (opening + cash sales/repayments − cash expenses in the
              // session's window) — not vs. the opening amount alone, which
              // would flag every normal day of sales as "over."
              future: ref.read(cashSessionRepositoryProvider).expectedCash(session),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2));
                }
                final variance = closing - snap.data!;
                return Text(
                  variance == 0
                      ? l.cashVarianceExact
                      : (variance < 0
                          ? l.cashVarianceShort(Money(-variance).withSymbol(sym))
                          : l.cashVarianceOver(Money(variance).withSymbol(sym))),
                  style: TextStyle(
                    color: variance == 0
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                );
              },
            ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.amountLabel,
    required this.confirmLabel,
  });
  final String title;
  final String amountLabel;
  final String confirmLabel;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: widget.amountLabel,
          suffixText: l.currencySymbol,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(_amount.text.trim()) ?? 0;
            Navigator.of(context).pop(v);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
