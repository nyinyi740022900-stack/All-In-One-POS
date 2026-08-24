/// Pure: the Balance Sheet's figures, folded by the provider from the same
/// sources the individual screens already show.
///
/// This ledger was not born from a double-entry GL — opening stock is set
/// by manual "opening" movements that have no matching cash/equity event —
/// so Assets − Liabilities − Equity is NOT guaranteed to be zero. That
/// difference is surfaced honestly as [untracked] (typically the value the
/// owner entered as opening stock, ± manual adjustments) rather than
/// silently forced into retained earnings.
class BalanceSheet {
  final int cashAndAccounts;
  final int inventoryValue;
  final int receivables;
  final int payables;
  final int paidInCapital;
  final int retainedEarnings;

  const BalanceSheet({
    required this.cashAndAccounts,
    required this.inventoryValue,
    required this.receivables,
    required this.payables,
    required this.paidInCapital,
    required this.retainedEarnings,
  });

  int get assets => cashAndAccounts + inventoryValue + receivables;
  int get liabilities => payables;
  int get equityTotal => paidInCapital + retainedEarnings;

  /// Assets − Liabilities − Equity. Zero for a shop whose books started
  /// from cash alone; non-zero by the untracked opening stock/adjustments.
  int get untracked => assets - liabilities - equityTotal;
}
