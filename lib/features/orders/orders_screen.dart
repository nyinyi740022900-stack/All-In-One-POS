import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'order_detail_sheet.dart';
import 'order_editor_sheet.dart';
import 'order_labels.dart';
import 'orders_providers.dart';
import 'orders_repository.dart';

/// The Social Orders list: a flat, newest-first list filtered by search /
/// channel / payment / status. On medium+ widths, master–detail shows the
/// selected order inline; phones still open [OrderDetailSheet].
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.embedded = false});

  /// When true, builds only the list / master–detail body — no [Scaffold],
  /// [AppBar] or FAB — so `OrdersInvoicesHubScreen` can host it under its own
  /// chrome as a sub-tab. Default (false) keeps the original standalone
  /// full-screen behaviour.
  final bool embedded;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String? _selectedOrderId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ordersAsync = ref.watch(ordersStreamProvider);
    final filtered = ref.watch(filteredOrdersListProvider);
    final split = isMediumPlus(context);

    if (_selectedOrderId != null &&
        !filtered.any((o) => o.id == _selectedOrderId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedOrderId = null);
      });
    }

    void openOrder(Order order) {
      if (split) {
        setState(() => _selectedOrderId = order.id);
      } else {
        OrderDetailSheet.show(context, order.id);
      }
    }

    final listBody = ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
      data: (all) {
        if (all.isEmpty) {
          return EmptyStateView(
            icon: Icons.dashboard_customize_outlined,
            title: l.ordersEmpty,
          );
        }
        return Column(
          children: [
            const _FilterHeader(),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyStateView(
                      icon: Icons.search_off,
                      title: l.ordersNoMatch,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.space3,
                        AppTheme.space1,
                        AppTheme.space3,
                        AppTheme.space3,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _OrderCard(
                        order: filtered[i],
                        selected: split && filtered[i].id == _selectedOrderId,
                        onTap: () => openOrder(filtered[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );

    final body = split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: widthClassOf(context) == AppWidthClass.expanded ? 42 : 45,
                child: listBody,
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: widthClassOf(context) == AppWidthClass.expanded ? 58 : 55,
                child: _selectedOrderId == null
                    ? EmptyStateView(
                        icon: Icons.receipt_long_outlined,
                        title: l.ordersSelectHint,
                      )
                    : OrderDetailSheet(
                        orderId: _selectedOrderId!,
                        embedded: true,
                      ),
              ),
            ],
          )
        : listBody;

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l.ordersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => OrderEditorSheet.show(context),
        icon: const Icon(Icons.add),
        label: Text(l.orderNew),
      ),
      body: body,
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
    final active =
        ref.watch(ordersFilterActiveProvider) ||
        ref.watch(orderStatusFilterProvider) != null;
    final channel = ref.watch(orderChannelFilterProvider);
    final payment = ref.watch(orderPaymentFilterProvider);
    final status = ref.watch(orderStatusFilterProvider);
    final grouped = ref.watch(ordersByStatusProvider);
    final cancelledCount = (grouped['cancelled'] ?? const []).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space3,
        AppTheme.space2,
        AppTheme.space3,
        0,
      ),
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
            onChanged: (v) => ref.read(orderSearchProvider.notifier).state = v,
          ),
          const SizedBox(height: AppTheme.space2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in orderStatuses)
                  _FilterChip(
                    label:
                        '${orderStatusLabel(l, s)} (${(grouped[s] ?? const []).length})',
                    selected: status == s,
                    onSelected: () =>
                        ref.read(orderStatusFilterProvider.notifier).state =
                            (status == s ? null : s),
                  ),
                if (cancelledCount > 0)
                  _FilterChip(
                    label:
                        '${orderStatusLabel(l, 'cancelled')} ($cancelledCount)',
                    selected: status == 'cancelled',
                    onSelected: () =>
                        ref.read(orderStatusFilterProvider.notifier).state =
                            (status == 'cancelled' ? null : 'cancelled'),
                  ),
                const SizedBox(width: AppTheme.space3),
                for (final c in orderChannels)
                  _FilterChip(
                    label: orderChannelLabel(l, c),
                    selected: channel == c,
                    onSelected: () =>
                        ref.read(orderChannelFilterProvider.notifier).state =
                            (channel == c ? null : c),
                  ),
                const SizedBox(width: AppTheme.space3),
                for (final p in const ['unpaid', 'paid'])
                  _FilterChip(
                    label: orderPaymentLabel(l, p),
                    selected: payment == p,
                    onSelected: () =>
                        ref.read(orderPaymentFilterProvider.notifier).state =
                            (payment == p ? null : p),
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
      padding: const EdgeInsets.only(right: AppTheme.space2),
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
  const _OrderCard({
    required this.order,
    required this.onTap,
    this.selected = false,
  });
  final Order order;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sym = l.currencySymbol;
    final total = order.itemsTotal + order.deliveryFee;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space2),
      child: Card(
        margin: EdgeInsets.zero,
        color: selected ? scheme.secondaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      orderChannelIcon(order.channel),
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: AppTheme.space1),
                    Expanded(
                      child: Text(
                        order.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StatusDot(status: order.status),
                  ],
                ),
                const SizedBox(height: AppTheme.space1),
                Text(
                  order.orderNo,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.space2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Money(total).withSymbol(sym),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _PayDot(status: order.paymentStatus),
                  ],
                ),
                if ((order.deliveryCarrier ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space1),
                  Row(
                    children: [
                      Icon(
                        Icons.local_shipping_outlined,
                        size: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: AppTheme.space1),
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
          width: AppTheme.space2,
          height: AppTheme.space2,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppTheme.space1),
        Text(
          orderStatusLabel(l, status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c),
        ),
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
      'paid' => AppColors.of(context).success,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: AppTheme.space2, color: color),
        const SizedBox(width: AppTheme.space1),
        Text(
          orderPaymentLabel(l, status),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
