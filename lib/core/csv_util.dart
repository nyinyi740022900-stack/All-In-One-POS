/// Minimal RFC-4180-ish CSV helpers — no dependency needed for output this
/// simple (flat rows of strings/numbers). Quotes a field only when it
/// contains a comma, quote, or newline; doubles any embedded quotes.
String csvField(Object? value) {
  final s = '${value ?? ''}';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvRow(List<Object?> fields) => fields.map(csvField).join(',');

String csvDocument(List<String> header, List<List<Object?>> rows) {
  final lines = [csvRow(header), for (final r in rows) csvRow(r)];
  return lines.join('\r\n');
}
