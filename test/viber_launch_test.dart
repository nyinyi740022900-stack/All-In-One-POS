import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/support/viber_launch.dart';

void main() {
  test('viberChatNumber turns a Myanmar 09 local number into 959…', () {
    expect(viberChatNumber('09 123 456 789'), '959123456789');
    expect(viberChatNumber('+95 9 123 456 789'), '959123456789');
    expect(viberChatNumber('959123456789'), '959123456789');
    expect(viberChatNumber('00959123456789'), '959123456789');
  });

  test('viberChatNumber rejects empty or too-short values', () {
    expect(viberChatNumber(''), isNull);
    expect(viberChatNumber('abc'), isNull);
    expect(viberChatNumber('09123'), isNull);
  });

  test('viberChatUri uses the chat deep link with no plus sign', () {
    expect(
      viberChatUri('09123456789')?.toString(),
      'viber://chat?number=959123456789',
    );
  });
}
