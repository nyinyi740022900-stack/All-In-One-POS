import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phone_validator.dart';
import '../../core/theme/app_theme.dart';
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
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final address = TextEditingController(text: existing?.address ?? '');
    var tier = existing?.tier ?? 'retail';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? l.customerAdd : l.customerEdit),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l.customerNameLabel),
                ),
                const SizedBox(height: AppTheme.space2),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l.customerPhone,
                    helperText: looksLikeMyanmarPhone(phone.text)
                        ? null
                        : l.phoneFormatHint,
                    helperMaxLines: 2,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: AppTheme.space2),
                TextField(
                  controller: address,
                  decoration: InputDecoration(labelText: l.customerAddress),
                ),
                const SizedBox(height: AppTheme.space2),
                DropdownButtonFormField<String>(
                  initialValue: tier,
                  decoration: InputDecoration(labelText: l.customerTierLabel),
                  items: [
                    DropdownMenuItem(
                        value: 'retail', child: Text(l.customerTierRetail)),
                    DropdownMenuItem(
                        value: 'wholesale',
                        child: Text(l.customerTierWholesale)),
                    DropdownMenuItem(
                        value: 'vip', child: Text(l.customerTierVip)),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => tier = v ?? 'retail'),
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
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;

    await ref.read(customerRepositoryProvider).upsertCustomer(
          id: existing?.id,
          name: name.text.trim(),
          phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          address: address.text.trim().isEmpty ? null : address.text.trim(),
          tier: tier,
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
    final loading = ref.watch(customersStreamProvider).isLoading;
    final creditCustomers = ref.watch(creditCustomersProvider);
    final owedById = <String, int>{
      for (final c in creditCustomers)
        if (c.customerId != null) c.customerId!: c.outstanding,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l.customersTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.space4, 0, AppTheme.space4, AppTheme.space2),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.customersSearchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(customerSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.customerAdd),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : customers.isEmpty
              ? Center(child: Text(l.customersEmpty))
              : ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = customers[i];
                    final owed = owedById[c.id] ?? 0;
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
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.name),
                      subtitle: subtitleParts.isEmpty
                          ? null
                          : Text(subtitleParts.join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (owed > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.account_balance_wallet,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, ref, c),
                          ),
                        ],
                      ),
                      onTap: owed > 0
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CreditCustomerScreen(
                                  customerKey: creditKeyFor(c.id, c.name),
                                  customerName: c.name,
                                ),
                              ))
                          : () => _openEditor(context, ref, c),
                    );
                  },
                ),
    );
  }
}
