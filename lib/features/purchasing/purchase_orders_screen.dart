import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_providers.dart';

String poStatusLabel(AppLocalizations l, String status) => switch (status) {
      'received' => l.poStatusReceived,
      'cancelled' => l.poStatusCancelled,
      _ => l.poStatusOpen,
    };

/// The semantic weight of a purchase-order status, for [StatusPill] — mirrors
/// `orderStatusTone` in `order_labels.dart`. `open` is [StatusTone.attention]
/// (not neutral): an open PO is still waiting to be received, i.e. the shop's
/// to-do list, the same reasoning as a `new` social order. `cancelled` is
/// [StatusTone.neutral], not danger, for the same reason cancelled orders
/// aren't red — it is a finished-with state, not an error to chase.
StatusTone poStatusTone(String status) => switch (status) {
      'received' => StatusTone.positive,
      'cancelled' => StatusTone.neutral,
      _ => StatusTone.attention,
    };

/// Purchase orders: lightweight tracking of what's been ordered from
/// suppliers — not procurement automation. See `PurchaseOrderRepository`.
class PurchaseOrdersScreen extends ConsumerWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading || !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.purchaseOrdersTitle)),
        body: PremiumGate(featureName: l.purchaseOrdersTitle, child: const SizedBox.shrink()),
      );
    }
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
              ? EmptyStateView(
                  icon: Icons.local_shipping_outlined,
                  title: l.purchaseOrdersEmpty,
                  actionLabel: l.poCreate,
                  onAction: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PurchaseOrderEditorScreen(),
                  )),
                )
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final po = orders[i];
                    return ListTile(
                      leading: const IconAvatar(
                          icon: Icons.local_shipping_outlined),
                      title: Text('${po.poNo}  ·  ${po.supplierName}'),
                      subtitle: Text(df.format(po.createdAt)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                              Money(po.itemsTotal).withSymbol(l.currencySymbol)),
                          const SizedBox(height: AppTheme.space1),
                          StatusPill(
                            label: poStatusLabel(l, po.status),
                            tone: poStatusTone(po.status),
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
