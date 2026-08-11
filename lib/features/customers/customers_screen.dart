import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/phone_validator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../credit/credit_providers.dart';
import '../credit/credit_repository.dart';
import '../credit/credit_screen.dart';
import 'customer_providers.dart';

/// Customer directory: browse/search/add/edit the shop's saved customers —
/// enter a name/phone/address once and reuse it on invoices/orders instead
/// of retyping (see CustomerRepository).
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Customer c) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.customerDeleteConfirmTitle),
        content: Text(l.customerDeleteConfirmBody(c.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              // Removing a customer must not wear the same brand-green
              // affirmative as "Save".
              style: AppTheme.dangerFilledButtonStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(customerRepositoryProvider).deleteCustomer(c.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.customerDeleted)));
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [Customer? existing]) async {
    final l = AppLocalizations.of(context);
    final draft = await showDialog<_CustomerDraft>(
      context: context,
      builder: (_) => _CustomerEditorDialog(existing: existing),
    );
    if (draft == null) return;
    await ref.read(customerRepositoryProvider).upsertCustomer(
          id: existing?.id,
          name: draft.name,
          phone: draft.phone,
          address: draft.address,
          tier: draft.tier,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.customerSaved)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final customers = ref.watch(filteredCustomersProvider);
    final all = ref.watch(customersStreamProvider);
    final searching = ref.watch(customerSearchProvider).trim().isNotEmpty;
    final creditCustomers = ref.watch(creditCustomersProvider);
    final owedById = <String, int>{
      for (final c in creditCustomers)
        if (c.customerId != null) c.customerId!: c.outstanding,
    };

    return Scaffold(
      // The search field lives in the body, not in a fixed-height
      // `AppBar.bottom` `PreferredSize(56)`: that box could not grow, so a
      // Myanmar hint at 1.3x text scale was clipped by it. This also matches
      // Orders and Invoices, which both carry their search in the body.
      appBar: AppBar(title: Text(l.customersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.customerAdd),
      ),
      body: all.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTheme.space4,
                    AppTheme.space3,
                    AppTheme.space4,
                    AppTheme.space2,
                  ),
                  child: _CustomerSearchField(),
                ),
                Expanded(
                  child: customers.isEmpty
                      // A filtered-empty list is not an empty directory:
                      // offering "Add customer" as the answer to "no search
                      // matches" is the wrong action for that state.
                      ? searching
                          ? EmptyStateView(
                              icon: Icons.search_off,
                              title: l.customersNoMatch,
                            )
                          : EmptyStateView(
                              icon: Icons.people_outline,
                              title: l.customersEmpty,
                              actionLabel: l.customerAdd,
                              onAction: () => _openEditor(context, ref),
                            )
                      : ListView.separated(
                          padding: const EdgeInsets.only(
                            bottom: AppTheme.space6 * 2,
                          ),
                          itemCount: customers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final c = customers[i];
                            return _CustomerRow(
                              customer: c,
                              owed: owedById[c.id] ?? 0,
                              onEdit: () => _openEditor(context, ref, c),
                              onDelete: () => _confirmDelete(context, ref, c),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// One directory row.
///
/// Three fixes over the old `ListTile`:
/// * the leading mark was `CircleAvatar(child: Icon(Icons.person))` — the
///   *same* grey disc on every row, so it carried no information at all. It
///   now uses the shared [ProductThumb] identity plate, which gives each
///   customer a stable colour and initial (Myanmar gets one syllable, Latin
///   two) — the same mark language as the Sell grid and Inventory list;
/// * the credit indicator was a bare red wallet icon: it said *that* the
///   customer owed something but never *how much*, which is the only part a
///   shopkeeper actually needs. It's now a tappable [StatusPill] carrying the
///   tabular amount, and tapping it is what opens the credit book;
/// * delete was a naked trash icon sitting one thumb-width from the row's own
///   tap target. It moved into a labelled overflow menu (the pattern Inventory
///   adopted for the same reason).
///
/// The old row also overloaded one gesture with two destinations — tapping a
/// customer opened the credit screen if they owed money and the editor if they
/// didn't, so the same action did different things depending on data the user
/// couldn't see. Row tap now always edits.
class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.owed,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final int owed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = customer;
    final tierLabel = switch (c.tier) {
      'wholesale' => l.customerTierWholesale,
      'vip' => l.customerTierVip,
      _ => null,
    };
    final subtitleParts = [
      if ((c.phone ?? '').isNotEmpty) c.phone!,
      ?tierLabel,
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space1,
      ),
      leading: ProductThumb(
        name: c.name,
        size: 40,
        radius: AppTheme.radiusFull,
      ),
      title: Text(c.name),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(subtitleParts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (owed > 0)
            _OwedPill(customer: c, owed: owed),
          PopupMenuButton<void>(
            tooltip: l.commonMore,
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: onEdit,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l.commonEdit),
                ),
              ),
              PopupMenuItem<void>(
                onTap: onDelete,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l.commonDelete),
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: onEdit,
    );
  }
}

/// The outstanding balance, as the route into the credit book — the same
/// "the pill *is* the control" pattern Inventory uses for its stock badge.
class _OwedPill extends StatelessWidget {
  const _OwedPill({required this.customer, required this.owed});

  final Customer customer;
  final int owed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = l.invoiceOwed(Money(owed).withSymbol(l.currencySymbol));
    return Tooltip(
      message: l.creditTitle,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreditCustomerScreen(
              customerKey: creditKeyFor(customer.id, customer.name),
              customerName: customer.name,
            ),
          ),
        ),
        child: Semantics(
          button: true,
          label: '${l.creditTitle}, $label',
          excludeSemantics: true,
          // The pill is ~24pt tall on its own; this keeps the *target* at 48.
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space1),
            child: StatusPill(label: label, tone: StatusTone.attention),
          ),
        ),
      ),
    );
  }
}

class _CustomerSearchField extends ConsumerStatefulWidget {
  const _CustomerSearchField();

  @override
  ConsumerState<_CustomerSearchField> createState() =>
      _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends ConsumerState<_CustomerSearchField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(customerSearchProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final query = ref.watch(customerSearchProvider);
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: l.customersSearchHint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        // Without this, the only way out of a search that matches nothing was
        // to select the text and delete it by hand.
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: l.commonClear,
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref.read(customerSearchProvider.notifier).state = '';
                },
              ),
      ),
      onChanged: (v) => ref.read(customerSearchProvider.notifier).state = v,
    );
  }
}

/// What the editor dialog hands back. The dialog owns the controllers, so the
/// caller can't read `.text` off them after it closes — it gets trimmed,
/// normalized values instead.
class _CustomerDraft {
  const _CustomerDraft({
    required this.name,
    required this.phone,
    required this.address,
    required this.tier,
  });

  final String name;
  final String? phone;
  final String? address;
  final String tier;
}

/// Add/edit a customer.
///
/// **This is a crash fix, not a restyle.** The editor used to be a
/// `StatefulBuilder` inside `_openEditor`, which created three
/// `TextEditingController`s, `await`ed `showDialog`, and then disposed all
/// three. That future completes when the route is *popped*, not when its exit
/// animation has finished — so for the length of the close transition the
/// still-mounted `TextField`s were attached to disposed controllers, which
/// throws "A TextEditingController was used after being disposed" and paints a
/// red error screen over the app. Owning the controllers in a real
/// `StatefulWidget` ties their lifetime to the dialog's actual place in the
/// widget tree. (Third instance of this bug in the app: see
/// `checkout_sheet.dart`'s `_LineDiscountDialog` and `categories_screen.dart`'s
/// `_CategoryNameDialog`.)
class _CustomerEditorDialog extends StatefulWidget {
  const _CustomerEditorDialog({this.existing});

  final Customer? existing;

  @override
  State<_CustomerEditorDialog> createState() => _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends State<_CustomerEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late String _tier;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _address = TextEditingController(text: widget.existing?.address ?? '');
    _tier = widget.existing?.tier ?? 'retail';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      _CustomerDraft(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        tier: _tier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canSave = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.existing == null ? l.customerAdd : l.customerEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(labelText: l.customerNameLabel),
              // Save was silently a no-op on an empty name — the dialog
              // closed and nothing was written, with no explanation.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(
                labelText: l.customerPhone,
                helperText: looksLikeMyanmarPhone(_phone.text)
                    ? null
                    : l.phoneFormatHint,
                helperMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _address,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.fullStreetAddress],
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(labelText: l.customerAddress),
              onSubmitted: (_) {
                if (canSave) _save();
              },
            ),
            const SizedBox(height: AppTheme.space3),
            DropdownButtonFormField<String>(
              initialValue: _tier,
              decoration: InputDecoration(labelText: l.customerTierLabel),
              items: [
                DropdownMenuItem(
                    value: 'retail', child: Text(l.customerTierRetail)),
                DropdownMenuItem(
                    value: 'wholesale', child: Text(l.customerTierWholesale)),
                DropdownMenuItem(
                    value: 'vip', child: Text(l.customerTierVip)),
              ],
              onChanged: (v) => setState(() => _tier = v ?? 'retail'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
