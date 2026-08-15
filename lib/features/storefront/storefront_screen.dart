import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
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
  bool _hoursEnabled = false;
  int _openMinute = 9 * 60;
  int _closeMinute = 18 * 60;
  bool _requireProof = true;

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
    _hoursEnabled = row.hoursEnabled;
    _openMinute = row.openMinute ?? 9 * 60;
    _closeMinute = row.closeMinute ?? 18 * 60;
    _requireProof = row.requireTransferProof;
  }

  String _fmtMinute(int m) {
    final h = m ~/ 60;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  Future<void> _pickMinute({required bool open}) async {
    final initial = TimeOfDay(
      hour: (open ? _openMinute : _closeMinute) ~/ 60,
      minute: (open ? _openMinute : _closeMinute) % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      final m = picked.hour * 60 + picked.minute;
      if (open) {
        _openMinute = m;
      } else {
        _closeMinute = m;
      }
    });
  }

  Future<void> _publish() async {
    final l = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.storefrontNeedsName)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(storefrontRepositoryProvider)
          .publish(
            displayName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          );
      ref.invalidate(myStorefrontProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(storefrontRepositoryProvider)
          .updateProfile(
            displayName: _name.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim(),
            logoUrl: _logoUrl,
            payKpayName: _kpayName.text.trim(),
            payKpay: _kpayNumber.text.trim(),
            payWaveName: _waveName.text.trim(),
            payWave: _waveNumber.text.trim(),
            hoursEnabled: _hoursEnabled,
            openMinute: _openMinute,
            closeMinute: _closeMinute,
            requireTransferProof: _requireProof,
          );
      ref.invalidate(myStorefrontProvider);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.storefrontProfileSaved)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final url = await ref
          .read(storefrontRepositoryProvider)
          .uploadLogo(file.bytes!, ext);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(isEffectiveOwnerProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.storefrontTitle)),
        body: const OwnerOnlyGate(
          capability: OwnerCapability.storefront,
          child: SizedBox.shrink(),
        ),
      );
    }
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.storefrontTitle)),
        body: PremiumGate(
          featureName: l.storefrontTitle,
          child: const SizedBox.shrink(),
        ),
      );
    }
    final async = ref.watch(myStorefrontProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.storefrontTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
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
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        Text(l.storefrontDesc),
        const SizedBox(height: AppTheme.space4),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l.storefrontDisplayName,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTheme.space3),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l.storefrontPhoneShown,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTheme.space3),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l.storefrontAddressShown,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTheme.space4),
        FilledButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.public),
          label: Text(l.storefrontPublish),
        ),
      ],
    );
  }

  Widget _manageView(AppLocalizations l, StorefrontRow row) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: (_logoUrl ?? '').isEmpty
                    ? const Icon(Icons.storefront, size: 36)
                    : Image.network(
                        _logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
              ),
              const SizedBox(height: AppTheme.space2),
              TextButton.icon(
                onPressed: _uploadingLogo ? null : _pickLogo,
                icon: _uploadingLogo
                    ? const ButtonSpinner(size: 14)
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(l.storefrontLogoLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.storefrontDisplayName),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l.storefrontPhoneShown),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: InputDecoration(labelText: l.storefrontAddressShown),
        ),
        const Divider(height: AppTheme.space6),
        SectionHeader(title: l.storefrontPaymentInfoTitle),
        Text(
          l.storefrontPaymentInfoHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _kpayName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.storefrontPayKpayName),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _kpayNumber,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l.storefrontPayKpayNumber),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _waveName,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.storefrontPayWaveName),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _waveNumber,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l.storefrontPayWaveNumber),
        ),
        const Divider(height: AppTheme.space6),
        SectionHeader(title: l.storefrontHoursTitle),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.storefrontHoursEnabled),
          value: _hoursEnabled,
          onChanged: (v) => setState(() => _hoursEnabled = v),
        ),
        if (_hoursEnabled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.storefrontHoursOpen),
            trailing: Text(_fmtMinute(_openMinute)),
            onTap: () => _pickMinute(open: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.storefrontHoursClose),
            trailing: Text(_fmtMinute(_closeMinute)),
            onTap: () => _pickMinute(open: false),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.storefrontRequireProof),
          subtitle: Text(l.storefrontRequireProofHint),
          value: _requireProof,
          onChanged: (v) => setState(() => _requireProof = v),
        ),
        const SizedBox(height: AppTheme.space3),
        FilledButton.icon(
          onPressed: _busy ? null : _saveProfile,
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.check),
          label: Text(l.commonSave),
        ),
        const Divider(height: AppTheme.space6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.storefrontEnabled),
          value: row.enabled,
          onChanged: (v) async {
            await ref.read(storefrontRepositoryProvider).setEnabled(v);
            ref.invalidate(myStorefrontProvider);
          },
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          l.storefrontYourLink,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppTheme.space1),
        Card(
          child: ListTile(
            title: Text(row.url),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: row.url));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l.storefrontCopied)));
              },
            ),
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        FilledButton.tonalIcon(
          onPressed: () async {
            final name = (_name.text.trim().isEmpty)
                ? (row.displayName ?? l.storefrontShopFallbackName)
                : _name.text.trim();
            await SharePlus.instance.share(
              ShareParams(text: l.storefrontShareText(name, row.url)),
            );
          },
          icon: const Icon(Icons.share_outlined),
          label: Text(l.storefrontShareAction),
        ),
        const SizedBox(height: AppTheme.space2),
        Text(l.storefrontShare, style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: AppTheme.space6),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block),
          title: Text(l.storefrontBlockedCustomers),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _BlockedCustomersScreen()),
          ),
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

  /// The dialog's two `TextEditingController`s live inside
  /// [_AddBlockedCustomerDialog], not here. This used to create them inline,
  /// `await` `showDialog`, and never dispose them at all — a straight leak
  /// (nothing touched them after the `await`, so it never crashed), the same
  /// bug family as `checkout_sheet.dart`'s dispose-*after*-`await` crash
  /// (that one *did* red-screen, because it disposed on the next line while
  /// the `TextField` was still mounted — the future resolves on *pop*, before
  /// the exit animation finishes). Fixed the same way regardless: the
  /// controllers move into their own `StatefulWidget` so `dispose()` runs on
  /// real teardown.
  Future<void> _addBlock(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_BlockedCustomerDraft>(
      context: context,
      builder: (_) => const _AddBlockedCustomerDialog(),
    );
    if (draft == null || !context.mounted) return;
    await ref
        .read(storefrontRepositoryProvider)
        .block(draft.phone, reason: draft.reason);
    ref.invalidate(blockedCustomersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(blockedCustomersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.storefrontBlockedCustomers)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addBlock(context, ref),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyStateView(
              icon: Icons.block,
              title: l.storefrontNoBlockedCustomers,
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = rows[i];
              return ListTile(
                leading: const IconAvatar(icon: Icons.phone_disabled),
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

class _BlockedCustomerDraft {
  const _BlockedCustomerDraft(this.phone, this.reason);
  final String phone;
  final String? reason;
}

/// Phone + optional reason editor for blocking a storefront customer. A
/// `StatefulWidget` purely so its two controllers are owned by something
/// whose `dispose()` runs on real teardown — see
/// [_BlockedCustomersScreen._addBlock].
class _AddBlockedCustomerDialog extends StatefulWidget {
  const _AddBlockedCustomerDialog();

  @override
  State<_AddBlockedCustomerDialog> createState() =>
      _AddBlockedCustomerDialogState();
}

class _AddBlockedCustomerDialogState
    extends State<_AddBlockedCustomerDialog> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return;
    final reason = _reason.text.trim();
    Navigator.of(
      context,
    ).pop(_BlockedCustomerDraft(phone, reason.isEmpty ? null : reason));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.storefrontAddBlocked),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.customerPhone),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _reason,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l.storefrontBlockReasonOptional,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.orderBlockCustomer)),
      ],
    );
  }
}
