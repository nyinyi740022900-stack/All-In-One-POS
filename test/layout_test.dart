import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/core/layout.dart';

void main() {
  test('widthClassFor breakpoints', () {
    expect(widthClassFor(320), AppWidthClass.compact);
    expect(widthClassFor(639.9), AppWidthClass.compact);
    expect(widthClassFor(640), AppWidthClass.medium);
    expect(widthClassFor(1023), AppWidthClass.medium);
    expect(widthClassFor(1024), AppWidthClass.expanded);
  });
}
