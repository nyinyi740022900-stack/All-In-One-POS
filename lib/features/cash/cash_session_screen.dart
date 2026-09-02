import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/currency_def.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_data.dart';
import '../printing/document_print.dart';
import '../printing/printer_connection.dart';
import '../printing/printing_providers.dart';
import 'cash_providers.dart';
import 'cash_session_report_csv.dart';
import 'cash_session_report_formatter.dart';
import 'cash_session_report_pdf.dart';

/// "Exact" / "short by X" / "over by X" — shared by the close dialog's live
/// preview and the history tiles so the two can never drift apart.
String _varianceTextFor(
  AppLocalizations l,
  int variance,
  CurrencyDef currency,
  String locale,
) {
  if (variance == 0) return l.cashVarianceExact;
  return variance < 0
      ? l.cashVarianceShort(Money(-variance).withCurrency(currency, locale))
      : l.cashVarianceOver(Money(variance).withCurrency(currency, locale));
}

/// Cash-drawer session: open with a declared float, watch what the drawer
/// should hold live, close with a counted amount to see the variance.
class CashSessionScreen extends ConsumerWidget {
  const CashSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(currentCashSessionProvider).valueOrNull;
    final history =
        ref.watch(cashSessionHistoryProvider).valueOrNull ?? const [];
    final pastSessions = history.where((s) => s.id != session?.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l.cashRegisterTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          if (session == null)
            _ClosedCard(onOpen: () => _openRegister(context, ref))
          else
            _OpenCard(
              session: session,
              onClose: () => _closeRegister(context, ref, session),
            ),
          const SizedBox(height: AppTheme.space5),
          Text(l.cashHistory, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.space2),
          if (pastSessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
              child: Text(
                l.cashNoHistory,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...pastSessions.map(
              (s) => _HistoryTile(key: ValueKey(s.id), session: s),
            ),
        ],
      ),
    );
  }

  Future<void> _openRegister(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final currency = ref.read(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l.cashOpenRegister,
        amountLabel: l.cashOpeningAmount,
        confirmLabel: l.cashOpenRegister,
        currency: currency,
        locale: locale,
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref
          .read(cashSessionRepositoryProvider)
          .openSession(openingAmount: amount, deviceId: deviceId);
      messenger.showSnackBar(SnackBar(content: Text(l.cashRegisterOpenedMsg)));
    } on StateError catch (e) {
      // Repository guard (audit QA-M4) — the screen only offers Open when
      // its watch says none is open, so this is the stale-UI / double-tap
      // path.
      if (e.message.contains('session_already_open')) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.cashSessionAlreadyOpen)));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  Future<void> _closeRegister(
    BuildContext context,
    WidgetRef ref,
    CashSession session,
  ) async {
    final l = AppLocalizations.of(context);
    final currency = ref.read(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final expected = ref.read(expectedCashProvider).valueOrNull;
    if (expected == null) return;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l.cashCloseRegister,
        amountLabel: l.cashClosingAmount,
        confirmLabel: l.cashCloseRegister,
        warningText: l.cashCloseWarning,
        // The figure the cashier is counting AGAINST — without it inside the
        // dialog they'd have to memorise it off the card behind the overlay.
        expectedCash: expected,
        currency: currency,
        locale: locale,
      ),
    );
    if (amount == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(cashSessionRepositoryProvider)
          .closeSession(session.id, closingAmount: amount);
      messenger.showSnackBar(SnackBar(content: Text(l.cashRegisterClosedMsg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }
}

class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: AppTheme.space2),
                Expanded(child: Text(l.cashNoSession)),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.lock_open),
              label: Text(l.cashOpenRegister),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCard extends ConsumerWidget {
  const _OpenCard({required this.session, required this.onClose});
  final CashSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final expected = ref.watch(expectedCashProvider);
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final colors = AppColors.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatusPill(
              label: l.cashRegisterOpen,
              tone: StatusTone.positive,
              icon: Icons.lock_open,
            ),
            const SizedBox(height: AppTheme.space3),
            _kv(context, l.cashOpenedAt, Text(df.format(session.openedAt))),
            _kv(
              context,
              l.cashOpeningAmount,
              MoneyText(Money(session.openingAmount).withCurrency(currency, locale)),
            ),
            const Divider(height: AppTheme.space5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l.cashExpectedNow,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                expected.when(
                  loading: () => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  // Tap to retry — a dead '—' tooltip left the till's core
                  // number unrecoverable until the screen was reopened.
                  error: (e, _) => Tooltip(
                    message: l.commonUnexpectedError,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      onTap: () => ref.invalidate(expectedCashProvider),
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.space1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: colors.danger,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l.commonRetry,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.danger),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  data: (v) => MoneyText(
                    Money(v ?? 0).withCurrency(currency, locale),
                    emphasis: true,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            // Cash physically added to the drawer mid-session (e.g. the
            // owner covering a shortfall from their own pocket) — without
            // this the only way to reflect real cash added to the till was
            // to close the register and reopen with a new float, discarding
            // everything already recorded for the current session.
            OutlinedButton.icon(
              onPressed: () => _addTopUp(context, ref),
              icon: const Icon(Icons.add_card_outlined),
              label: Text(l.cashAddTopUp),
            ),
            const SizedBox(height: AppTheme.space2),
            // Lets the owner see WHAT makes up "Expected cash now" (cash
            // sales/repayments in vs. expenses/supplier payments out) before
            // deciding whether/how to close — previously this breakdown was
            // only ever available AFTER closing, via the history row's own
            // report icon, which is too late to catch a mis-recorded entry.
            OutlinedButton.icon(
              onPressed: () => showCashReportSheet(context, ref, session),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(l.cashReportTitle),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: expected.hasValue && expected.valueOrNull != null
                  ? onClose
                  : null,
              icon: const Icon(Icons.lock_outline),
              label: Text(l.cashCloseRegister),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTopUp(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final currency = ref.read(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(
        title: l.cashAddTopUp,
        amountLabel: l.cashTopUpAmount,
        confirmLabel: l.cashAddTopUp,
        currency: currency,
        locale: locale,
      ),
    );
    if (amount == null || amount <= 0 || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cashSessionRepositoryProvider).addTopUp(amount: amount);
      messenger.showSnackBar(SnackBar(content: Text(l.cashTopUpSaved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  Widget _kv(BuildContext context, String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          value,
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerStatefulWidget {
  const _HistoryTile({super.key, required this.session});
  final CashSession session;

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile> {
  /// A closed session's window is frozen (`closedAt` is set), so its
  /// expected figure never changes — compute ONCE instead of re-querying on
  /// every parent rebuild (the old per-build `ref.read` inside
  /// FutureBuilder re-ran the whole sales/expenses window query each time).
  late final Future<int> _expected = ref
      .read(cashSessionRepositoryProvider)
      .expectedCash(widget.session);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final session = widget.session;
    final closing = session.closingAmount;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        closing == null ? Icons.lock_open : Icons.lock_outline,
        color: closing == null ? AppColors.of(context).success : null,
      ),
      title: Text(df.format(session.openedAt)),
      subtitle: Text(
        closing == null
            ? l.cashRegisterOpen
            : '${l.cashOpeningAmount}: ${Money(session.openingAmount).withCurrency(currency, locale)}'
                  ' → ${l.cashClosingAmount}: ${Money(closing).withCurrency(currency, locale)}',
      ),
      trailing: closing == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<int>(
                  // Variance is counted cash vs. what the drawer *should*
                  // hold (opening + cash sales/repayments − cash expenses in
                  // the session's window) — not vs. the opening amount
                  // alone, which would flag every normal day of sales as
                  // "over."
                  future: _expected,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    // An errored read used to spin forever (`!hasData`
                    // caught errors too) — show an honest dash instead.
                    if (snap.hasError || snap.data == null) {
                      return Tooltip(
                        message: l.commonUnexpectedError,
                        child: Text(
                          '—',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.of(context).muted),
                        ),
                      );
                    }
                    final variance = closing - snap.data!;
                    final colors = AppColors.of(context);
                    return Text(
                      _varianceTextFor(l, variance, currency, locale),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: variance == 0 ? colors.success : colors.danger,
                      ),
                    );
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.receipt_long_outlined),
                  tooltip: l.cashReportTitle,
                  onPressed: () =>
                      showCashReportSheet(context, ref, widget.session),
                ),
              ],
            ),
    );
  }
}

/// Print/Share entry point for a session's itemized breakdown (opening float,
/// cash sales/repayments in, expenses/supplier payments out, expected cash,
/// and — once closed — counted cash + variance). Shared by [_HistoryTile]
/// (a closed session) and [_OpenCard] (the currently open one, so the owner
/// can see WHY "Expected cash now" is whatever it is — e.g. a large supplier
/// payment recorded as cash — without having to close the register first to
/// get a report). `reportFor`/`buildCashSessionReportPdf`/
/// `buildCashSessionReportCsv`/`CashSessionReportFormatter` all already
/// handle a null `closedAt`/`closingAmount`/`variance` gracefully, so no
/// change was needed there — this only had to stop being private to
/// [_HistoryTileState].
Future<void> showCashReportSheet(
  BuildContext context,
  WidgetRef ref,
  CashSession session,
) async {
  final l = AppLocalizations.of(context);
  final printerConfig = await ref.read(printerConfigProvider.future);
  if (!context.mounted) return;
  await showAppModal<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: Text(l.documentPrint),
            onTap: () {
              Navigator.pop(ctx);
              _printPdf(context, ref, session);
            },
          ),
          if (printerConfig.hasPrinter)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(l.cashReportPrintBluetooth),
              onTap: () {
                Navigator.pop(ctx);
                _printReport(
                  context,
                  ref,
                  session,
                  printerConfig.mac!,
                  printerConfig.paper,
                  printerConfig.connection,
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l.cashReportSharePdf),
            onTap: () {
              Navigator.pop(ctx);
              _sharePdf(context, ref, session);
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(l.cashReportShareCsv),
            onTap: () {
              Navigator.pop(ctx);
              _shareCsv(context, ref, session);
            },
          ),
        ],
      ),
    ),
  );
}

Future<Uint8List> _pdfBytes(
    BuildContext context, WidgetRef ref, CashSession session) async {
  final l = AppLocalizations.of(context);
  final currency = ref.read(shopCurrencyProvider);
  final locale = Localizations.localeOf(context).languageCode;
  final report =
      await ref.read(cashSessionRepositoryProvider).reportFor(session);
  final varianceText = report.variance == null
      ? null
      : _varianceTextFor(l, report.variance!, currency, locale);
  final profile = await ref.read(shopProfileProvider.future);
  final printerConfig = await ref.read(printerConfigProvider.future);
  return buildCashSessionReportPdf(
    shopName: profile.name,
    shopLogoUrl: profile.logoUrl,
    shopPhone: profile.phone,
    shopAddress: profile.address,
    title: l.cashReportTitle,
    report: report,
    currencySymbol: currency.label(locale),
    exponent: currency.exponent,
    openedLabel: l.cashOpenedAt,
    closedLabel: l.cashClosedAt,
    openingFloatLabel: l.cashOpeningAmount,
    cashSalesLabel: l.cashReportCashSales,
    cashRepaymentsLabel: l.cashReportCashRepayments,
    topUpsLabel: l.cashReportTopUps,
    expensesLabel: l.expensesTitle,
    supplierPaymentsLabel: l.cashReportSupplierPayments,
    expectedCashLabel: l.cashExpectedNow,
    countedCashLabel: l.cashClosingAmount,
    openedAt: session.openedAt,
    closedAt: session.closedAt,
    varianceLabel: l.cashVariance,
    varianceText: varianceText,
    pageFormat: printerConfig.pdfPaperSize,
  );
}

Future<void> _printPdf(
    BuildContext context, WidgetRef ref, CashSession session) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await _pdfBytes(context, ref, session);
    if (!context.mounted) return;
    await printPdfDocument(bytes: bytes, name: l.cashReportTitle);
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

Future<void> _printReport(
  BuildContext context,
  WidgetRef ref,
  CashSession session,
  String mac,
  PaperSize paper,
  PrinterConnection connection,
) async {
  final l = AppLocalizations.of(context);
  final currency = ref.read(shopCurrencyProvider);
  final locale = Localizations.localeOf(context).languageCode;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final report =
        await ref.read(cashSessionRepositoryProvider).reportFor(session);
    final varianceText = report.variance == null
        ? null
        : _varianceTextFor(l, report.variance!, currency, locale);
    final lines =
        CashSessionReportFormatter(
          paper: paper,
          currencySymbol: currency.label(locale),
          exponent: currency.exponent,
        ).format(
          report,
          title: l.cashReportTitle,
          openedLabel: l.cashOpenedAt,
          closedLabel: l.cashClosedAt,
          openingFloatLabel: l.cashOpeningAmount,
          cashSalesLabel: l.cashReportCashSales,
          cashRepaymentsLabel: l.cashReportCashRepayments,
          topUpsLabel: l.cashReportTopUps,
          expensesLabel: l.expensesTitle,
          supplierPaymentsLabel: l.cashReportSupplierPayments,
          expectedCashLabel: l.cashExpectedNow,
          countedCashLabel: l.cashClosingAmount,
          openedAt: session.openedAt,
          closedAt: session.closedAt,
          varianceLabel: l.cashVariance,
          varianceText: varianceText,
        );
    final profile = await ref.read(shopProfileProvider.future);
    final result = await ref
        .read(printerServiceProvider)
        .printZReport(
          lines,
          profile.name,
          paper: paper,
          mac: mac,
          connection: connection,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(result.ok ? l.printSuccess : l.printFailed)),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

Future<void> _sharePdf(
    BuildContext context, WidgetRef ref, CashSession session) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await _pdfBytes(context, ref, session);
    final dir = await getTemporaryDirectory();
    // Dated so a shop sharing a week of reports to the owner can tell
    // them apart in the chat thread.
    final stamp = DateFormat(
      'yyyyMMdd-HHmm',
    ).format(session.closedAt ?? session.openedAt);
    final file = File('${dir.path}/cash-report-$stamp.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: l.cashReportTitle,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

Future<void> _shareCsv(
    BuildContext context, WidgetRef ref, CashSession session) async {
  final l = AppLocalizations.of(context);
  final currency = ref.read(shopCurrencyProvider);
  final locale = Localizations.localeOf(context).languageCode;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final report =
        await ref.read(cashSessionRepositoryProvider).reportFor(session);
    final varianceText = report.variance == null
        ? null
        : _varianceTextFor(l, report.variance!, currency, locale);
    final csv = buildCashSessionReportCsv(
      report,
      openingFloatLabel: l.cashOpeningAmount,
      cashSalesLabel: l.cashReportCashSales,
      cashRepaymentsLabel: l.cashReportCashRepayments,
      topUpsLabel: l.cashReportTopUps,
      expensesLabel: l.expensesTitle,
      supplierPaymentsLabel: l.cashReportSupplierPayments,
      expectedCashLabel: l.cashExpectedNow,
      countedCashLabel: l.cashClosingAmount,
      varianceLabel: l.cashVariance,
      varianceText: varianceText,
      lineHeader: l.pnlLine,
      amountHeader: '${l.pnlAmount} (${currency.label(locale)})',
      exponent: currency.exponent,
    );
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat(
      'yyyyMMdd-HHmm',
    ).format(session.closedAt ?? session.openedAt);
    final file = File('${dir.path}/cash-report-$stamp.csv');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: l.cashReportTitle,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.amountLabel,
    required this.confirmLabel,
    required this.currency,
    required this.locale,
    this.warningText,
    this.expectedCash,
  });
  final String title;
  final String amountLabel;
  final String confirmLabel;
  final String? warningText;
  final CurrencyDef currency;
  final String locale;

  /// Close-flow only: the drawer's expected contents, shown above the field
  /// with a live variance preview as the cashier types their count — the
  /// last chance to catch a miscount before the (final) close commits.
  final int? expectedCash;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// An empty confirm used to fall through `int.tryParse('') ?? 0` and
  /// record counted=0 — an irreversible −expected variance. Empty is now a
  /// validation error; an explicit "0" stays allowed (a genuinely empty
  /// float/drawer is legitimate).
  void _submit() {
    if (_amount.text.trim().isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context).cashAmountRequired,
      );
      return;
    }
    Navigator.of(context).pop(int.tryParse(_amount.text.trim()) ?? 0);
  }

  /// Live variance under the field while typing the count — green when it
  /// matches expectations, red with the short/over figure otherwise.
  List<Widget> _variancePreview(BuildContext context, AppLocalizations l) {
    if (widget.expectedCash == null || _amount.text.trim().isEmpty) {
      return const [];
    }
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null) return const [];
    final variance = amount - widget.expectedCash!;
    final colors = AppColors.of(context);
    final color = variance == 0 ? colors.success : colors.danger;
    return [
      const SizedBox(height: AppTheme.space1),
      Row(
        children: [
          Icon(
            variance == 0 ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppTheme.space1),
          Expanded(
            child: Text(
              _varianceTextFor(l, variance, widget.currency, widget.locale),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.expectedCash != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space2),
              child: SummaryRow(
                l.cashExpectedNow,
                Money(widget.expectedCash!).withCurrency(widget.currency, widget.locale),
                emphasis: true,
              ),
            ),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // Rebuilds on every keystroke so the live variance preview tracks
            // the count, and any validation error clears as soon as they type.
            onChanged: (_) => setState(() {
              if (_error != null) _error = null;
            }),
            decoration: InputDecoration(
              labelText: widget.amountLabel,
              suffixText: widget.currency.label(widget.locale),
              errorText: _error,
            ),
          ),
          ..._variancePreview(context, l),
          if (widget.warningText != null) ...[
            const SizedBox(height: AppTheme.space2),
            Text(
              widget.warningText!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
