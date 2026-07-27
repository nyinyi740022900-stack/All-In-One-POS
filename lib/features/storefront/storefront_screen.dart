import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import 'storefront_repository.dart';

final storefrontRepositoryProvider = Provider<StorefrontRepository>((ref) {
  return StorefrontRepository(ref.watch(shopIdProvider));
});

final myStorefrontProvider = FutureProvider<StorefrontRow?>((ref) {
  return ref.watch(storefrontRepositoryProvider).mine();
});

final blockedCustomersProvider = FutureProvider<List<BlockedCustomer>>((ref) {
  return ref.watch(storefrontRepositoryProvider).listBlocked();
});

/// Owner screen to publish/manage the shop's public web storefront: name,
/// phone, address, logo, and the enabled toggle + shareable link.
class StorefrontScreen extends ConsumerStatefulWidget {
  const StorefrontScreen({super.key});

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _kpayName = TextEditingController();
  final _kpayNumber = TextEditingController();
  final _waveName = TextEditingController();
  final _waveNumber = TextEditingController();
  bool _busy = false;
  bool _uploadingLogo = false;
  String? _logoUrl;
  bool _initializedFromRow = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _kpayName.dispose();
    _kpayNumber.dispose();
    _waveName.dispose();
    _waveNumber.dispose();
    super.dispose();
  }

  void _initFrom(StorefrontRow row) {
    if (_initializedFromRow) return;
    _initializedFromRow = true;
    _name.text = row.displayName ?? '';
    _phone.text = row.phone ?? '';
    _address.text = row.address ?? '';
    _logoUrl = row.logoUrl;
    _kpayName.text = row.payKpayName ?? '';
    _kpayNumber.text = row.payKpay ?? '';
    _waveName.text = row.payWaveName ?? '';
    _waveNumber.text = row.payWave ?? '';
  }

  Future<void> _publish() async {
    final l = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.storefrontNeedsName)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(storefrontRepositoryProvider).publish(
            displayName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            address:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
          );
      ref.invalidate(myStorefrontProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      await ref.read(storefrontRepositoryProvider).updateProfile(
            displayName: _name.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim(),
            logoUrl: _logoUrl,
            payKpayName: _kpayName.text.trim(),
            payKpay: _kpayNumber.text.trim(),
            payWaveName: _waveName.text.trim(),
            payWave: _waveNumber.text.trim(),
          );
      ref.invalidate(myStorefrontProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickLogo() async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final url =
          await ref.read(storefrontRepositoryProvider).uploadLogo(file.bytes!, ext);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(myStorefrontProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.storefrontTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (row) {
          if (row == null) return _publishForm(l);
          _initFrom(row);
          return _manageView(l, row);
        },
      ),
    );
  }

  Widget _publishForm(AppLocalizations l) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.storefrontDesc),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l.storefrontDisplayName,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (shown to customers)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Address (shown to customers)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.public),
          label: Text(l.storefrontPublish),
        ),
      ],
    );
  }

  Widget _manageView(AppLocalizations l, StorefrontRow row) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: (_logoUrl ?? '').isEmpty
                    ? const Icon(Icons.storefront, size: 36)
                    : Image.network(_logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _uploadingLogo ? null : _pickLogo,
                icon: _uploadingLogo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Shop logo'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration:
              InputDecoration(labelText: l.storefrontDisplayName),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const Divider(height: 32),
        Text(l.storefrontPaymentInfoTitle,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l.storefrontPaymentInfoHint,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          controller: _kpayName,
          textCapitalization: TextCapitalization.words,
          decoration:
              InputDecoration(labelText: l.storefrontPayKpayName),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _kpayNumber,
          keyboardType: TextInputType.phone,
          decoration:
              InputDecoration(labelText: l.storefrontPayKpayNumber),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _waveName,
          textCapitalization: TextCapitalization.words,
          decoration:
              InputDecoration(labelText: l.storefrontPayWaveName),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _waveNumber,
          keyboardType: TextInputType.phone,
          decoration:
              InputDecoration(labelText: l.storefrontPayWaveNumber),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _saveProfile,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
        ),
        const Divider(height: 32),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.storefrontEnabled),
          value: row.enabled,
          onChanged: (v) async {
            await ref.read(storefrontRepositoryProvider).setEnabled(v);
            ref.invalidate(myStorefrontProvider);
          },
        ),
        const SizedBox(height: 8),
        Text(l.storefrontYourLink,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Card(
          child: ListTile(
            title: Text(row.url),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: row.url));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.storefrontCopied)));
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.storefrontShare,
            style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block),
          title: Text(l.storefrontBlockedCustomers),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _BlockedCustomersScreen(),
          )),
        ),
      ],
    );
  }
}

/// Lists phone numbers the owner has blocked from placing new storefront
/// orders (see [OrderDetailSheet]'s "Block this customer" action), with an
/// unblock action for each.
class _BlockedCustomersScreen extends ConsumerWidget {
  const _BlockedCustomersScreen();

  Future<void> _addBlock(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final phone = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.storefrontAddBlocked),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(labelText: l.customerPhone),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              decoration:
                  InputDecoration(labelText: l.storefrontBlockReasonOptional),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.orderBlockCustomer)),
        ],
      ),
    );
    if (ok != true || phone.text.trim().isEmpty) return;
    await ref.read(storefrontRepositoryProvider).block(
          phone.text.trim(),
          reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
        );
    ref.invalidate(blockedCustomersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(blockedCustomersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.storefrontBlockedCustomers)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addBlock(context, ref, l),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(child: Text(l.storefrontNoBlockedCustomers));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = rows[i];
              return ListTile(
                leading: const Icon(Icons.phone_disabled),
                title: Text(b.phone),
                subtitle: (b.reason ?? '').isEmpty ? null : Text(b.reason!),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(storefrontRepositoryProvider)
                        .unblock(b.phone);
                    ref.invalidate(blockedCustomersProvider);
                  },
                  child: Text(l.storefrontUnblock),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
