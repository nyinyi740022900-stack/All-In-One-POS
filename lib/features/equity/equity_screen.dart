import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounting/accounting_providers.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';
import 'equity_calculator.dart';
import 'equity_csv.dart';
import 'equity_pdf.dart';
import 'equity_providers.dart';

/// Owner's Equity: capital contributions + drawings, plus Retained
/// Earnings (cumulative Net Profit since inception) — deliberately
/// separate from Expenses so a drawing never reduces the P&L's Net
/// Profit. Toward an eventual Balance Sheet.
class OwnerEquityScreen extends ConsumerStatefulWidget {
  const OwnerEquityScreen({super.key});

  @override
  ConsumerState<OwnerEquityScreen> createState() => _OwnerEquityScreenState();
}

class _OwnerEquityScreenState extends ConsumerState<OwnerEquityScreen> {
  bool _exportingPdf = false;
  bool _exportingCsv = false;

  Widget _row(BuildContext context, String label, int amount, String currency,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: SummaryRow(
        label,
        Money(amount).withSymbol(currency),
        emphasis: bold,
      ),
    );
  }

  Future<Uint8List> _pdfBytes(EquitySummary summary,
      List<EquityEntry> entries, AppLocalizations l) async {
    final profile = await ref.read(shopProfileProvider.future);
    final printerConfig = await ref.read(printerConfigProvider.future);
    return buildEquityPdf(
      shopName: profile.name,
      shopLogoUrl: profile.logoUrl,
      shopPhone: profile.phone,
      shopAddress: profile.address,
      title: l.equityTitle,
      summary: summary,
      entries: entries,
      currencySymbol: l.currencySymbol,
      paidInCapitalLabel: l.equityPaidInCapital,
      retainedEarningsLabel: l.equityRetainedEarnings,
      totalEquityLabel: l.equityTotal,
      dateColumnLabel: l.stockHistoryHeaderDate,
      typeColumnLabel: l.stockHistoryHeaderType,
      noteColumnLabel: l.stockHistoryHeaderNote,
      amountColumnLabel: l.equityAmount,
      contributionLabel: l.equityContribution,
      drawingLabel: l.equityDrawing,
      pageFormat: printerConfig.pdfPaperSize,
    );
  }

  Future<void> _exportPdf(EquitySummary summary, List<EquityEntry> entries) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingPdf = true);
    try {
      final bytes = await _pdfBytes(summary, entries, l);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/owners-equity.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.equityTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportCsv(EquitySummary summary, List<EquityEntry> entries) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingCsv = true);
    try {
      final csv = buildEquityCsv(
        summary,
        entries,
        dateHeader: l.stockHistoryHeaderDate,
        typeHeader: l.stockHistoryHeaderType,
        noteHeader: l.stockHistoryHeaderNote,
        amountHeader: l.equityAmount,
        contributionLabel: l.equityContribution,
        drawingLabel: l.equityDrawing,
        paidInCapitalLabel: l.equityPaidInCapital,
        retainedEarningsLabel: l.equityRetainedEarnings,
        totalEquityLabel: l.equityTotal,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/owners-equity.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.equityTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.equityTitle)),
        body: PremiumGate(
          featureName: l.equityTitle,
          benefits: [l.equityBenefit1, l.equityBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final cur = l.currencySymbol;
    final entries = ref.watch(equityEntriesProvider).valueOrNull ?? const [];
    final summaryAsync = ref.watch(equitySummaryProvider);
    final df = DateFormat('yyyy-MM-dd');
    final colors = AppColors.of(context);
    final summary = summaryAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.equityTitle),
        actions: [
          IconButton(
            tooltip: l.salesReportExportPdf,
            icon: _exportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: summary == null || _exportingPdf
                ? null
                : () => _exportPdf(summary, entries),
          ),
          IconButton(
            tooltip: l.salesReportExportCsv,
            icon: _exportingCsv
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_chart_outlined),
            onPressed: summary == null || _exportingCsv
                ? null
                : () => _exportCsv(summary, entries),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(AppTheme.space4),
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ErrorRetryView(
                message: l.commonUnexpectedError,
                onRetry: () => ref.invalidate(equitySummaryProvider),
              ),
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, l.equityPaidInCapital, s.paidInCapital, cur),
                  _row(context, l.equityRetainedEarnings, s.retainedEarnings,
                      cur),
                  const Divider(),
                  _row(context, l.equityTotal, s.totalEquity, cur, bold: true),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? EmptyStateView(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l.equityEmpty,
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isContribution = e.type == equityTypeContribution;
                      return ListTile(
                        leading: IconAvatar(
                          icon: isContribution
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          tone: isContribution
                              ? StatusTone.positive
                              : StatusTone.critical,
                        ),
                        title: Text(isContribution
                            ? l.equityContribution
                            : l.equityDrawing),
                        subtitle: Text(
                          e.note == null || e.note!.isEmpty
                              ? df.format(e.date)
                              : '${df.format(e.date)} · ${e.note}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoneyText(
                              '${isContribution ? '+' : '-'}${Money(e.amount).withSymbol(cur)}',
                              emphasis: true,
                              color:
                                  isContribution ? colors.success : colors.danger,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l.commonDelete,
                              onPressed: () => _confirmDelete(context, ref, e),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, EquityEntry e) async {
    final l = AppLocalizations.of(context);
    // Year-end close: an entry dated in a closed book can't be deleted.
    final closedThrough = await ref.read(booksClosedThroughProvider.future);
    if (isDateInClosedBooks(closedThrough, e.date)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.yearEndClosedWarn(closedThrough!))),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.equityDeleteConfirmTitle),
        content: Text(l.equityDeleteConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(equityRepositoryProvider).deleteEntry(e.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.equityDeleted)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    }
  }

  Future<void> _openDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _EquityEntryDialog(),
    );
  }
}

class _EquityEntryDialog extends ConsumerStatefulWidget {
  const _EquityEntryDialog();

  @override
  ConsumerState<_EquityEntryDialog> createState() => _EquityEntryDialogState();
}

class _EquityEntryDialogState extends ConsumerState<_EquityEntryDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _type = equityTypeContribution;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountChanged);
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  bool get _amountValid => (int.tryParse(_amount.text.trim()) ?? 0) > 0;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    final closedThrough = await ref.read(booksClosedThroughProvider.future);
    if (isDateInClosedBooks(closedThrough, _date)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.yearEndClosedWarn(closedThrough!))),
      );
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(equityRepositoryProvider).addEntry(
            type: _type,
            amount: amount,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.equitySaved)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final df = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: Text(l.equityAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              // Selected fill already marks the choice. The default
              // checkmark steals width, so the long Myanmar contribution
              // label wraps to two lines only while selected and the
              // dialog jumps. Hide the icon; keep two-line room so a
              // wrap (or 1.3× text scale) cannot clip or resize.
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space2,
                  vertical: AppTheme.space2,
                ),
              ),
              segments: [
                ButtonSegment(
                  value: equityTypeContribution,
                  label: Text(
                    l.equityContribution,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
                ButtonSegment(
                  value: equityTypeDrawing,
                  label: Text(
                    l.equityDrawing,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(labelText: l.equityAmount),
            ),
            const SizedBox(height: AppTheme.space3),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(df.format(_date)),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.expenseNote),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _saving || !_amountValid ? null : _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
