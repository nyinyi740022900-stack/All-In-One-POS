import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../l10n/app_localizations.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_providers.dart';

String poStatusLabel(AppLocalizations l, String status) => switch (status) {
      'received' => l.poStatusReceived,
      'cancelled' => l.poStatusCancelled,
      _ => l.poStatusOpen,
    };

Color? poStatusColor(BuildContext context, String status) => switch (status) {
      'received' => Colors.green,
      'cancelled' => Theme.of(context).colorScheme.error,
      _ => null,
    };

/// Purchase orders: lightweight tracking of what's been ordered from
/// suppliers — not procurement automation. See `PurchaseOrderRepository`.
class PurchaseOrdersScreen extends ConsumerWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? const [];
    final loading = ref.watch(purchaseOrdersProvider).isLoading;
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: Text(l.purchaseOrdersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PurchaseOrderEditorScreen(),
        )),
        icon: const Icon(Icons.add),
        label: Text(l.poCreate),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? Center(child: Text(l.purchaseOrdersEmpty))
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final po = orders[i];
                    return ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text('${po.poNo}  ·  ${po.supplierName}'),
                      subtitle: Text(df.format(po.createdAt)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Money(po.itemsTotal).withSymbol(l.currencySymbol)),
                          Text(
                            poStatusLabel(l, po.status),
                            style: TextStyle(
                                fontSize: 12,
                                color: poStatusColor(context, po.status)),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PurchaseOrderDetailScreen(poId: po.id),
                      )),
                    );
                  },
                ),
    );
  }
}
