import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart' show ShopProfile;
import '../../data/sync/outbox_error.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart' show shopProfileProvider;
import '../settings/shop_profile_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import 'storefront_providers.dart';
import 'storefront_repository.dart';

/// Classifies a Storefront repository error into specific, actionable
/// guidance instead of a flat "something went wrong" — the RLS branch only
/// fires once the repository's own one-shot session-refresh retry
/// (`StorefrontRepository._withRlsRetry`) has already happened and still
/// failed, so "restart the app" is genuinely the next real step, not just a
/// retry of what already failed.
String _storefrontErrorMessage(AppLocalizations l, Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network') ||
      s.contains('connection')) {
    return l.commonNetworkError;
  }
  if (classifyOutboxError(e.toString()) == OutboxErrorClass.rls42501) {
    return l.storefrontSessionStale;
  }
  return l.commonUnexpectedError;
}

/// A load failure with an actual recovery path, not a dead-end message —
/// mirrors the error-view shape `branches_screen.dart` already established
/// (icon + message + retry button that invalidates the failed provider).
class _ErrorRetryView extends StatelessWidget {
  const _ErrorRetryView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.of(context).muted,
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.space4),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owner screen to publish/manage the shop's public web storefront. Name,
/// phone, address, logo, and payment accounts are edited once in Settings →
/// Shop profile and best-effort mirrored here — this screen only shows them
/// read-only, plus its own settings: hours, require-transfer-proof, the
/// enabled toggle, the shareable link, and blocked customers.
class StorefrontScreen extends ConsumerStatefulWidget {
  const StorefrontScreen({super.key});

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  bool _busy = false;
  bool _initializedFromRow = false;
  bool _hoursEnabled = false;
  int _openMinute = 9 * 60;
  int _closeMinute = 18 * 60;
  bool _requireProof = true;

  void _initFrom(StorefrontRow row) {
    if (_initializedFromRow) return;
    _initializedFromRow = true;
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

  /// First publish: pulls name/phone/address straight from the shop's own
  /// profile (Settings → Shop profile) instead of asking the owner to retype
  /// it — `_saveProfile` below pushes logo/payment accounts right after, so
  /// a freshly-published storefront starts fully in sync, not just name/
  /// phone/address (`publish`'s own insert doesn't set those columns).
  Future<void> _publish() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final p = await ref.read(shopProfileProvider.future);
      await ref
          .read(storefrontRepositoryProvider)
          .publish(
            displayName: p.name,
            phone: (p.phone ?? '').isEmpty ? null : p.phone,
            address: (p.address ?? '').isEmpty ? null : p.address,
          );
      await ref.read(storefrontRepositoryProvider).updateProfile(
            logoUrl: p.logoUrl ?? '',
            paymentMethods: p.paymentMethods ?? const [],
            currencyCode: p.currencyCode ?? 'MMK',
          );
      ref.invalidate(myStorefrontProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_storefrontErrorMessage(l, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves this screen's own settings only (hours/require-proof) — name/
  /// phone/address/logo/payment accounts are mirrored by
  /// `ShopProfileScreen._save` whenever the owner edits them there, not from
  /// this screen at all (see the class doc).
  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(storefrontRepositoryProvider)
          .updateProfile(
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
            content: Text(
              _storefrontErrorMessage(AppLocalizations.of(context), e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(hasOwnerCapabilityProvider(OwnerCapability.storefront))) {
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
          benefits: [l.storefrontBenefit1, l.storefrontBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final async = ref.watch(myStorefrontProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.storefrontTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorRetryView(
          message: _storefrontErrorMessage(l, e),
          onRetry: () => ref.invalidate(myStorefrontProvider),
        ),
        data: (row) {
          if (row == null) return _publishForm(l);
          _initFrom(row);
          return _manageView(l, row);
        },
      ),
    );
  }

  void _openShopProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShopProfileScreen()),
    );
  }

  /// Read-only summary of the fields now edited exclusively in Settings →
  /// Shop profile — used by both `_publishForm` (before a storefront row
  /// exists) and `_manageView` (after), so the owner sees the same "here's
  /// what's about to go out / what's already live" info in one shared shape.
  Widget _shopProfileSummary(AppLocalizations l, ShopProfile p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: (p.logoUrl ?? '').isEmpty
                  ? const Icon(Icons.storefront, size: 28)
                  : Image.network(
                      p.logoUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: ProductThumb.cacheWidthFor(
                          56, MediaQuery.devicePixelRatioOf(context)),
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            const SizedBox(width: AppTheme.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: Theme.of(context).textTheme.titleSmall),
                  if ((p.phone ?? '').isEmpty && (p.address ?? '').isEmpty)
                    Text(l.storefrontFromShopProfileHint,
                        style: Theme.of(context).textTheme.bodySmall)
                  else
                    Text(
                      [
                        if ((p.phone ?? '').isNotEmpty) p.phone,
                        if ((p.address ?? '').isNotEmpty) p.address,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _openShopProfile,
              child: Text(l.storefrontEditInShopProfile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _publishForm(AppLocalizations l) {
    final profile = ref.watch(shopProfileProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        Text(l.storefrontDesc),
        const SizedBox(height: AppTheme.space4),
        if (profile != null) _shopProfileSummary(l, profile),
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
    final profile = ref.watch(shopProfileProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        if (profile != null) _shopProfileSummary(l, profile),
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
            // A bare time with no chevron/pencil gave no visual signal the
            // row was tappable at all.
            trailing: _HoursValue(text: _fmtMinute(_openMinute)),
            onTap: () => _pickMinute(open: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.storefrontHoursClose),
            trailing: _HoursValue(text: _fmtMinute(_closeMinute)),
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
            try {
              await ref.read(storefrontRepositoryProvider).setEnabled(v);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _storefrontErrorMessage(AppLocalizations.of(context), e),
                    ),
                  ),
                );
              }
            } finally {
              // Re-fetch either way so the switch reflects the true server
              // state instead of staying visually toggled on a failed write.
              // Guarded: backing out while the write is in flight (offline,
              // it can hang until timeout) used to throw StateError out of
              // ref here as an unhandled exception.
              if (mounted) ref.invalidate(myStorefrontProvider);
            }
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previously the owner could Publish then Share a link
                // without ever confirming what a customer actually sees —
                // this is the missing "see it for myself" step.
                IconButton(
                  tooltip: l.storefrontViewAction,
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => launchUrl(
                    Uri.parse(row.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                IconButton(
                  tooltip: l.commonCopy,
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: row.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.storefrontCopied)));
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        FilledButton.tonalIcon(
          onPressed: () async {
            final name = row.displayName ?? l.storefrontShopFallbackName;
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
          subtitle: Text(l.storefrontBlockedHow),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const _BlockedCustomersScreen()),
          ),
        ),
      ],
    );
  }
}

/// Lists IPs the owner has blocked from placing new storefront
/// orders (see [OrderDetailSheet]'s "Block this IP" action), with an
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
    try {
      await ref
          .read(storefrontRepositoryProvider)
          .block(draft.ip, reason: draft.reason);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _storefrontErrorMessage(AppLocalizations.of(context), e),
            ),
          ),
        );
      }
    } finally {
      ref.invalidate(blockedCustomersProvider);
    }
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
        error: (e, _) => _ErrorRetryView(
          message: _storefrontErrorMessage(l, e),
          onRetry: () => ref.invalidate(blockedCustomersProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyStateView(
              icon: Icons.block,
              title: l.storefrontNoBlockedCustomers,
              message: l.storefrontBlockedHow,
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = rows[i];
              return ListTile(
                leading: const IconAvatar(icon: Icons.public_off),
                title: Text(b.ip),
                subtitle: (b.reason ?? '').isEmpty ? null : Text(b.reason!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l.copied,
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: b.ip));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.orderIpCopied)),
                        );
                      },
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(storefrontRepositoryProvider)
                              .unblock(b.ip);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _storefrontErrorMessage(
                                    AppLocalizations.of(context),
                                    e,
                                  ),
                                ),
                              ),
                            );
                          }
                        } finally {
                          ref.invalidate(blockedCustomersProvider);
                        }
                      },
                      child: Text(l.storefrontUnblock),
                    ),
                  ],
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
  const _BlockedCustomerDraft(this.ip, this.reason);
  final String ip;
  final String? reason;
}

/// IP + optional reason editor for blocking a storefront client. A
/// `StatefulWidget` purely so its two controllers are owned by something
/// whose `dispose()` runs on real teardown — see
/// [_BlockedCustomersScreen._addBlock].
class _AddBlockedCustomerDialog extends StatefulWidget {
  const _AddBlockedCustomerDialog();

  @override
  State<_AddBlockedCustomerDialog> createState() =>
      _AddBlockedCustomerDialogState();
}

class _AddBlockedCustomerDialogState extends State<_AddBlockedCustomerDialog> {
  final _ip = TextEditingController();
  final _reason = TextEditingController();
  String? _ipError;

  @override
  void dispose() {
    _ip.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final ip = normalizeStorefrontIp(_ip.text);
    if (ip.isEmpty) {
      setState(() => _ipError = AppLocalizations.of(context).storefrontIpInvalid);
      return;
    }
    final reason = _reason.text.trim();
    Navigator.of(
      context,
    ).pop(_BlockedCustomerDraft(ip, reason.isEmpty ? null : reason));
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
            controller: _ip,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l.storefrontIpAddress,
              errorText: _ipError,
            ),
            onChanged: (_) {
              if (_ipError != null) setState(() => _ipError = null);
            },
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

/// An hours row's trailing time, with a small chevron so the row visibly
/// invites a tap instead of reading as a plain (non-interactive) label.
class _HoursValue extends StatelessWidget {
  const _HoursValue({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(width: AppTheme.space1),
        Icon(
          Icons.chevron_right,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
      ],
    );
  }
}
