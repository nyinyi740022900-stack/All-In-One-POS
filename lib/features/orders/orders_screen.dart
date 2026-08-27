import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      loading: () => const AppLoadingView(),
      error: (e, _) => ErrorRetryView(
        message: l.commonUnexpectedError,
        onRetry: () => ref.invalidate(ordersStreamProvider),
      ),
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
                      // Stable per-order keys (audit Low): when the list
                      // shifts (new order lands via sync), elements match by
                      // identity instead of position.
                      itemBuilder: (context, i) => _OrderCard(
                        key: ValueKey('order-${filtered[i].id}'),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space3,
        AppTheme.space2,
        AppTheme.space3,
        AppTheme.space2,
      ),
      child: TextField(
        controller: _search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: l.ordersSearchHint,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active)
                IconButton(
                  tooltip: l.ordersClearFilters,
                  icon: const Icon(Icons.clear),
                  onPressed: _clearAll,
                ),
              IconButton(
                tooltip: l.commonFilters,
                icon: Badge(
                  isLabelVisible: active,
                  smallSize: 8,
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: () => _openFilterSheet(context),
              ),
            ],
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => ref.read(orderSearchProvider.notifier).state = v,
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    showChipFilterSheet(
      context,
      title: l.commonFilters,
      clearLabel: l.ordersClearFilters,
      onClearAll: _clearAll,
      sectionsBuilder: (refresh) {
        final status = ref.read(orderStatusFilterProvider);
        final channel = ref.read(orderChannelFilterProvider);
        final payment = ref.read(orderPaymentFilterProvider);
        final grouped = ref.read(ordersByStatusProvider);
        final cancelledCount = (grouped['cancelled'] ?? const []).length;
        return [
          FilterChipSection(
            chips: [
              for (final s in orderStatuses)
                FilterChipSpec(
                  label:
                      '${orderStatusLabel(l, s)} (${(grouped[s] ?? const []).length})',
                  selected: status == s,
                  onTap: () {
                    ref.read(orderStatusFilterProvider.notifier).state =
                        status == s ? null : s;
                    refresh();
                  },
                ),
              if (cancelledCount > 0)
                FilterChipSpec(
                  label:
                      '${orderStatusLabel(l, 'cancelled')} ($cancelledCount)',
                  selected: status == 'cancelled',
                  onTap: () {
                    ref.read(orderStatusFilterProvider.notifier).state =
                        status == 'cancelled' ? null : 'cancelled';
                    refresh();
                  },
                ),
            ],
          ),
          FilterChipSection(
            chips: [
              for (final c in orderChannels)
                FilterChipSpec(
                  label: orderChannelLabel(l, c),
                  selected: channel == c,
                  onTap: () {
                    ref.read(orderChannelFilterProvider.notifier).state =
                        channel == c ? null : c;
                    refresh();
                  },
                ),
            ],
          ),
          FilterChipSection(
            chips: [
              for (final p in const ['unpaid', 'paid'])
                FilterChipSpec(
                  label: orderPaymentLabel(l, p),
                  selected: payment == p,
                  onTap: () {
                    ref.read(orderPaymentFilterProvider.notifier).state =
                        payment == p ? null : p;
                    refresh();
                  },
                ),
            ],
          ),
        ];
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
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
                    StatusPill(
                      label: orderStatusLabel(l, order.status),
                      tone: orderStatusTone(order.status),
                      showDot: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space1),
                // When the order came in — a social-order pipeline is worked
                // oldest-first, and without a timestamp on the card every
                // row looks equally urgent.
                Text(
                  '${order.orderNo} · '
                  '${DateFormat('dd/MM HH:mm').format(order.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: AppTheme.tabularFigures,
                  ),
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

/// The card's payment line — deliberately the *lighter* of the two status
/// marks on an order card. The pipeline status gets the full [StatusPill]
/// (it's the thing the shopkeeper acts on); payment stays a dot + label in
/// the same tone, so a card that is both `new` and `unpaid` reads as one
/// signal with a footnote rather than two competing pastel plates.
class _PayDot extends StatelessWidget {
  const _PayDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = orderPaymentTone(status).colors(AppColors.of(context)).on;
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
