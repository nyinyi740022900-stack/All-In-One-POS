import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'order_detail_sheet.dart';
import 'order_editor_sheet.dart';
import 'order_labels.dart';
import 'orders_providers.dart';
import 'orders_repository.dart';

/// The Social Orders list: a flat, newest-first list filtered by search /
/// channel / payment / status. Replaced the earlier horizontally-scrolling
/// Kanban board — with the pipeline collapsed to just New/Delivered (see
/// [orderStatuses]), a board's per-column layout no longer earned its
/// complexity; a simple filterable list reads faster on a phone screen.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ordersAsync = ref.watch(ordersStreamProvider);
    final filtered = ref.watch(filteredOrdersListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.ordersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => OrderEditorSheet.show(context),
        icon: const Icon(Icons.add),
        label: Text(l.orderNew),
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          // Nothing in the DB at all → the first-run empty state (no filters).
          if (all.isEmpty) {
            return _EmptyState(
                icon: Icons.dashboard_customize_outlined,
                message: l.ordersEmpty);
          }
          return Column(
            children: [
              const _FilterHeader(),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(
                        icon: Icons.search_off, message: l.ordersNoMatch)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) =>
                            _OrderCard(order: filtered[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Search box + channel/payment/status filter chips above the list.
class _FilterHeader extends ConsumerStatefulWidget {
  const _FilterHeader();

  @override
  ConsumerState<_FilterHeader> createState() => _FilterHeaderState();
}

class _FilterHeaderState extends ConsumerState<_FilterHeader> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(orderSearchProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearAll() {
    _search.clear();
    ref.read(orderSearchProvider.notifier).state = '';
    ref.read(orderChannelFilterProvider.notifier).state = null;
    ref.read(orderPaymentFilterProvider.notifier).state = null;
    ref.read(orderStatusFilterProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = ref.watch(ordersFilterActiveProvider) ||
        ref.watch(orderStatusFilterProvider) != null;
    final channel = ref.watch(orderChannelFilterProvider);
    final payment = ref.watch(orderPaymentFilterProvider);
    final status = ref.watch(orderStatusFilterProvider);
    final grouped = ref.watch(ordersByStatusProvider);
    final cancelledCount = (grouped['cancelled'] ?? const []).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l.ordersSearchHint,
              suffixIcon: active
                  ? IconButton(
                      tooltip: l.ordersClearFilters,
                      icon: const Icon(Icons.clear),
                      onPressed: _clearAll,
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(orderSearchProvider.notifier).state = v,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in orderStatuses)
                  _FilterChip(
                    label:
                        '${orderStatusLabel(l, s)} (${(grouped[s] ?? const []).length})',
                    selected: status == s,
                    onSelected: () => ref
                        .read(orderStatusFilterProvider.notifier)
                        .state = (status == s ? null : s),
                  ),
                if (cancelledCount > 0)
                  _FilterChip(
                    label: '${orderStatusLabel(l, 'cancelled')} ($cancelledCount)',
                    selected: status == 'cancelled',
                    onSelected: () => ref
                        .read(orderStatusFilterProvider.notifier)
                        .state = (status == 'cancelled' ? null : 'cancelled'),
                  ),
                const SizedBox(width: 12),
                for (final c in orderChannels)
                  _FilterChip(
                    label: orderChannelLabel(l, c),
                    selected: channel == c,
                    onSelected: () => ref
                        .read(orderChannelFilterProvider.notifier)
                        .state = (channel == c ? null : c),
                  ),
                const SizedBox(width: 12),
                for (final p in const ['unpaid', 'partial', 'paid'])
                  _FilterChip(
                    label: orderPaymentLabel(l, p),
                    selected: payment == p,
                    onSelected: () => ref
                        .read(orderPaymentFilterProvider.notifier)
                        .state = (payment == p ? null : p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sym = l.currencySymbol;
    final total = order.itemsTotal + order.deliveryFee;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => OrderDetailSheet.show(context, order.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(orderChannelIcon(order.channel),
                        size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(order.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    _StatusDot(status: order.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(order.orderNo,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(Money(total).withSymbol(sym),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    _PayDot(status: order.paymentStatus),
                  ],
                ),
                if ((order.deliveryCarrier ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.local_shipping_outlined,
                          size: 12, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          order.deliveryCarrier!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = orderStatusColor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(orderStatusLabel(l, status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
      ],
    );
  }
}

class _PayDot extends StatelessWidget {
  const _PayDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = switch (status) {
      'paid' => Colors.green,
      'partial' => Colors.orange,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(orderPaymentLabel(l, status),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 56, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
