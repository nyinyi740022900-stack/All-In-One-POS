/// Cash-tender suggestions for a checkout total.
///
/// Pure integer math, no Flutter — a cashier at the counter thinks in notes,
/// not in typing nine digits. Circulating Myanmar notes below 500 kyat exist
/// (50/100/200) but rounding a 12,500 sale up to 12,600 is not how anyone
/// hands over cash, so the smallest step here is 500.
const kyatNotes = [500, 1000, 5000, 10000, 20000];

/// Exact first, then the next few round-ups onto [kyatNotes].
///
/// Caps at [maxChips] so the wrap stays thumb-tappable on a phone. When the
/// total already sits on every note (e.g. 20,000), still offers one overpay
/// (`total + 20,000`) so the cashier can tap instead of typing two notes.
List<int> cashTenderSuggestions(int totalKyat, {int maxChips = 4}) {
  if (totalKyat <= 0) return const [];
  final extras = <int>{};
  for (final note in kyatNotes) {
    final rounded = _ceilTo(totalKyat, note);
    if (rounded > totalKyat) extras.add(rounded);
  }
  if (extras.isEmpty) extras.add(totalKyat + kyatNotes.last);
  final sorted = extras.toList()..sort();
  final room = maxChips - 1;
  if (room <= 0) return [totalKyat];
  return [totalKyat, ...sorted.take(room)];
}

int _ceilTo(int value, int step) => ((value + step - 1) ~/ step) * step;
