import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_providers.dart';
import 'purchase_orders_screen.dart';

/// One purchase order's detail — line items, total, and (while `open`) the
/// "Mark as Received" / "Cancel" actions. See `PurchaseOrderRepository`.
class PurchaseOrderDetailScreen extends ConsumerWidget {
  const PurchaseOrderDetailScreen({super.key, required this.poId});
  final String poId;

  Future<void> _confirmReceive(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.poReceiveConfirmTitle),
        content: Text(l.poReceiveConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.poMarkReceived)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(purchaseOrderRepositoryProvider).receivePO(poId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.poReceived)));
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.poCancelConfirmTitle),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.poCancelOrder)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(purchaseOrderRepositoryProvider).cancelPO(poId);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.poDeleteConfirmTitle),
        content: Text(l.poDeleteConfirmBody),
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
    await ref.read(purchaseOrderRepositoryProvider).deletePO(poId);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;
    final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? const [];
    final po = orders.where((o) => o.id == poId).firstOrNull;
    final items = ref.watch(purchaseOrderItemsProvider(poId)).valueOrNull ?? const [];
    final df = DateFormat('yyyy-MM-dd HH:mm');

    if (po == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.purchaseOrdersTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isOpen = po.status == 'open';

    return Scaffold(
      appBar: AppBar(
        title: Text(po.poNo),
        actions: [
          if (isOpen)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PurchaseOrderEditorScreen(
                    existing: po, existingItems: items),
              )),
            ),
          if (isOpen)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(po.supplierName,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(width: AppTheme.space2),
              StatusPill(
                label: poStatusLabel(l, po.status),
                tone: poStatusTone(po.status),
              ),
            ],
          ),
          Text(df.format(po.createdAt),
              style: Theme.of(context).textTheme.bodySmall),
          if (po.note != null && po.note!.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space2),
            Text(po.note!),
          ],
          const Divider(height: AppTheme.space5),
          for (final it in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(it.nameSnapshot),
              subtitle: Text(
                  '${it.qty} x ${Money(it.unitCost).withSymbol(cur)}'),
              trailing: MoneyText(Money(it.lineTotal).withSymbol(cur)),
            ),
          const Divider(),
          SummaryRow(l.commonTotal, Money(po.itemsTotal).withSymbol(cur),
              emphasis: true),
          if (isOpen) ...[
            const SizedBox(height: AppTheme.space4),
            FilledButton.icon(
              onPressed: () => _confirmReceive(context, ref),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(l.poMarkReceived),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton(
              onPressed: () => _confirmCancel(context, ref),
              child: Text(l.poCancelOrder),
            ),
          ],
        ],
      ),
    );
  }
}
