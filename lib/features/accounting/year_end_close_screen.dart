import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart' show settingsRepositoryProvider;
import 'accounting_providers.dart';

/// Year-end Close — mark a year's books as closed. Money records dated on
/// or before Dec 31 of the chosen year are then locked against edits and
/// deletes (Expenses, Equity entries) ON THIS DEVICE, and the closed
/// period is badged on the Balance Sheet. Reopening is one tap. The close
/// is a device-local per-shop marker (see
/// [SettingsRepository.booksClosedThrough]) — sales are append-only and
/// were never editable, so the lock only needs to cover the mutable money
/// records.
class YearEndCloseScreen extends ConsumerStatefulWidget {
  const YearEndCloseScreen({super.key});

  @override
  ConsumerState<YearEndCloseScreen> createState() => _YearEndCloseScreenState();
}

class _YearEndCloseScreenState extends ConsumerState<YearEndCloseScreen> {
  bool _working = false;

  Future<void> _close(int year) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.yearEndConfirmTitle(year)),
        content: Text(l.yearEndConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.accountingYearEndClose),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    try {
      final shopId = ref.read(shopIdProvider);
      await ref
          .read(settingsRepositoryProvider)
          .setBooksClosedThrough(shopId, '$year-12-31');
      ref.invalidate(booksClosedThroughProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l.yearEndClosedChip('$year-12-31'))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.commonUnexpectedError)),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reopen() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .clearBooksClosedThrough(ref.read(shopIdProvider));
      ref.invalidate(booksClosedThroughProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.yearEndReopened)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.commonUnexpectedError)),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.accountingYearEndClose)),
        body: PremiumGate(
          featureName: l.accountingYearEndClose,
          benefits: [l.pnlBenefit1, l.pnlBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final closedThrough = ref.watch(booksClosedThroughProvider).valueOrNull;
    final closedYear = closedThrough == null || closedThrough.isEmpty
        ? null
        : int.tryParse(closedThrough.split('-').first);
    final thisYear = DateTime.now().year;
    // Years worth closing: the last 5, oldest first — the picker is short
    // enough that a dropdown beats a full date dialog.
    final years = [
      for (var y = thisYear - 4; y <= thisYear; y++) y,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.accountingYearEndClose)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          StatusPill(
            label: closedThrough == null || closedThrough.isEmpty
                ? l.yearEndOpenChip
                : l.yearEndClosedChip(closedThrough),
            tone: closedThrough == null || closedThrough.isEmpty
                ? StatusTone.positive
                : StatusTone.neutral,
          ),
          const SizedBox(height: AppTheme.space3),
          Text(
            l.yearEndExplainer,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTheme.space4),
          if (closedYear == null) ...[
            for (final y in years.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.space2),
                child: OutlinedButton.icon(
                  onPressed: _working ? null : () => _close(y),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l.yearEndCloseThroughYear(y)),
                ),
              ),
          ] else ...[
            FilledButton.icon(
              onPressed: _working ? null : _reopen,
              icon: _working
                  ? const ButtonSpinner()
                  : const Icon(Icons.lock_open),
              label: Text(l.yearEndReopen),
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.yearEndReopenNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
