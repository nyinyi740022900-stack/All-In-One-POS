import '../../data/local/database.dart';

/// One payment account's money movement over a period — the per-account row
/// of the Cash Flow screen. Timing folds by `createdAt` (the physical money
/// moment), matching QA-M6's drawer decision; a business-dated expense that
/// was *recorded* in-period still moved the real balance when it was
/// recorded.
class AccountCashFlow {
  final String accountId;
  final String name;
  final int opening;
  final int inflow;
  final int outflow;

  const AccountCashFlow({
    required this.accountId,
    required this.name,
    required this.opening,
    required this.inflow,
    required this.outflow,
  });

  int get closing => opening + inflow - outflow;
}

/// Pure: per-account opening → inflow → outflow → closing for [start,
/// endExclusive), from the same four tables [computeAccountBalance] folds
/// (sale tenders + credit repayments in; expenses + supplier payments out).
/// Owner capital contributions/drawings are NOT account movements (no
/// account/method column) and are deliberately out of this statement — the
/// screen says so.
List<AccountCashFlow> computeCashFlows({
  required List<PaymentAccount> accounts,
  required List<Payment> payments,
  required List<CreditPayment> repayments,
  required List<Expense> expenses,
  required List<SupplierPayment> supplierPayments,
  required DateTime start,
  required DateTime endExclusive,
}) {
  bool inRange(DateTime at) =>
      !at.isBefore(start) && at.isBefore(endExclusive);

  int inflowFor(String accountId) =>
      payments
          .where((p) => p.method == accountId && inRange(p.createdAt))
          .fold<int>(0, (s, p) => s + p.amount) +
      repayments
          .where((r) => r.method == accountId && inRange(r.createdAt))
          .fold<int>(0, (s, r) => s + r.amount);

  int outflowFor(String accountId) =>
      expenses
          .where((e) => e.accountId == accountId && inRange(e.createdAt))
          .fold<int>(0, (s, e) => s + e.amount) +
      supplierPayments
          .where((p) => p.method == accountId && inRange(p.createdAt))
          .fold<int>(0, (s, p) => s + p.amount);

  int openingFor(String accountId, int openingBalance) {
    bool before(Payment p) =>
        p.method == accountId && p.createdAt.isBefore(start);
    bool beforeRepay(CreditPayment r) =>
        r.method == accountId && r.createdAt.isBefore(start);
    bool beforeExpense(Expense e) =>
        e.accountId == accountId && e.createdAt.isBefore(start);
    bool beforeSupplier(SupplierPayment p) =>
        p.method == accountId && p.createdAt.isBefore(start);
    return openingBalance +
        payments.where(before).fold<int>(0, (s, p) => s + p.amount) +
        repayments.where(beforeRepay).fold<int>(0, (s, r) => s + r.amount) -
        expenses.where(beforeExpense).fold<int>(0, (s, e) => s + e.amount) -
        supplierPayments.where(beforeSupplier).fold<int>(0, (s, p) => s + p.amount);
  }

  return [
    for (final a in accounts)
      AccountCashFlow(
        accountId: a.id,
        name: a.name,
        opening: openingFor(a.id, a.openingBalance),
        inflow: inflowFor(a.id),
        outflow: outflowFor(a.id),
      ),
  ];
}
