import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'customer_providers.dart';

/// Customer name field with directory suggestions: typing filters the
/// shop's saved customers by name/phone; picking one fills phone too.
/// Typing without picking anything still works exactly like a plain text
/// field — callers resolve/create a directory entry by name at save time
/// either way. Shared by checkout and the Social Orders editor.
class CustomerAutocomplete extends ConsumerWidget {
  const CustomerAutocomplete({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.labelText,
    required this.onChanged,
    required this.onSelected,
    required this.onEditedByHand,
    this.helperText,
  });

  final TextEditingController controller;
  // Owned by the parent State, not created here — this widget rebuilds on
  // every keystroke (onChanged triggers a parent setState) and whenever the
  // customer directory changes, so a FocusNode instantiated inline in
  // build() would get a new identity on every one of those rebuilds,
  // resetting the text input connection mid-typing (visible as the soft
  // keyboard briefly flipping to the wrong type).
  final FocusNode focusNode;
  final String labelText;
  final String? helperText;
  final VoidCallback onChanged;
  final ValueChanged<Customer> onSelected;
  final VoidCallback onEditedByHand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersStreamProvider).valueOrNull ?? const [];
    return RawAutocomplete<Customer>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<Customer>.empty();
        return customers.where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.contains(q) ?? false));
      },
      displayStringForOption: (c) => c.name,
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        final l = AppLocalizations.of(context);
        return TextField(
          controller: textController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: labelText,
            helperText: helperText,
            suffixIcon: IconButton(
              icon: const Icon(Icons.contacts_outlined),
              tooltip: l.checkoutPickCustomer,
              onPressed: () async {
                final picked = await showModalBottomSheet<Customer>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CustomerPickerSheet(customers: customers),
                );
                if (picked != null) onSelected(picked);
              },
            ),
          ),
          onChanged: (_) {
            onEditedByHand();
            onChanged();
          },
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final c in options)
                    ListTile(
                      dense: true,
                      title: Text(c.name),
                      subtitle: (c.phone ?? '').isEmpty ? null : Text(c.phone!),
                      onTap: () => onSelectedOption(c),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Browse-and-pick alternative to typing: a searchable, A–Z sorted list of
/// every directory customer, for someone who recognizes a name on sight but
/// doesn't want to (or can't easily) type it.
class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key, required this.customers});
  final List<Customer> customers;

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _search.text.trim().toLowerCase();
    final filtered = widget.customers
        .where((c) =>
            q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (c.phone?.contains(q) ?? false))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.space4, AppTheme.space4, AppTheme.space4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.customersTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.customersSearchHint,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTheme.space2),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(l.customersEmpty))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(c.name),
                          subtitle:
                              (c.phone ?? '').isEmpty ? null : Text(c.phone!),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
