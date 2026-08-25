import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mm_pos/features/printing/label_data.dart';
import 'package:mm_pos/features/printing/tspl.dart';

void main() {
  test('LabelSize converts mm to dots at 8 dots/mm', () {
    expect(LabelSize.mm40x30.widthDots, 320);
    expect(LabelSize.mm40x30.heightDots, 240);
    expect(LabelSize.mm50x40.widthDots, 400);
    expect(LabelSize.mm50x40.heightDots, 320);
  });

  test('buildTsplLabelBytes emits SIZE/GAP/BITMAP/BARCODE/PRINT commands',
      () {
    final image = img.Image(width: 16, height: 8); // white by default
    final bytes = buildTsplLabelBytes(
      nameImage: image,
      priceText: '1,000 Ks',
      barcodeValue: 'ABC-001',
      size: LabelSize.mm50x40,
      copies: 3,
    );
    final text = ascii.decode(bytes, allowInvalid: true);

    expect(text, contains('SIZE 50 mm,40 mm'));
    expect(text, contains('GAP 2 mm,0 mm'));
    expect(text, contains('BITMAP 0,4,2,8,0,'));
    expect(text, contains('TEXT'));
    expect(text, contains('"1,000 Ks"'));
    expect(text, contains('BARCODE'));
    expect(text, contains('"128"'));
    expect(text, contains('"ABC-001"'));
    expect(text, contains('PRINT 1,3'));
  });

  test('an all-white image packs to all-zero bitmap bytes', () {
    final image = img.Image(width: 16, height: 2);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final bytes = buildTsplLabelBytes(
      nameImage: image,
      priceText: 'x',
      barcodeValue: 'AB',
      size: LabelSize.mm40x30,
    );
    final text = ascii.decode(bytes, allowInvalid: true);
    final header = 'BITMAP 0,4,2,2,0,';
    final start = text.indexOf(header) + header.length;
    // 2 bytes/row * 2 rows = 4 payload bytes, all zero (white = no ink).
    final payload = bytes.sublist(start, start + 4);
    expect(payload, [0, 0, 0, 0]);
  });

  test('a fully black image packs to all-1 bitmap bytes', () {
    final image = img.Image(width: 8, height: 1);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    final bytes = buildTsplLabelBytes(
      nameImage: image,
      priceText: 'x',
      barcodeValue: 'AB',
      size: LabelSize.mm40x30,
    );
    final header = 'BITMAP 0,4,1,1,0,';
    final text = ascii.decode(bytes, allowInvalid: true);
    final start = text.indexOf(header) + header.length;
    expect(bytes[start], 0xFF);
  });

  test('short barcode values are skipped (below the module minimum)', () {
    final image = img.Image(width: 8, height: 8);
    final bytes = buildTsplLabelBytes(
      nameImage: image,
      priceText: 'x',
      barcodeValue: 'A',
      size: LabelSize.mm40x30,
    );
    final text = ascii.decode(bytes, allowInvalid: true);
    expect(text, isNot(contains('BARCODE')));
  });

  group('small-roll layout (30x20mm = 240x160 dots)', () {
    // Parses "BARCODE x,y,"128",h,..." out of the command stream.
    RegExp barcodeCmd(String text) =>
        RegExp(r'BARCODE (\d+),(\d+),"128",(\d+)');

    test('keeps its barcode with 1-dot bars (2-dot bars are wider than '
        'the roll)', () {
      final image = img.Image(width: 240, height: 90);
      final text = ascii.decode(
        buildTsplLabelBytes(
          nameImage: image,
          priceText: '1,000 Ks',
          barcodeValue: 'TEST0001',
          size: LabelSize.mm30x20,
        ),
        allowInvalid: true,
      );
      final m = barcodeCmd(text).firstMatch(text);
      expect(m, isNotNull);
      expect(m!.group(1), '10'); // x
      // narrow=wide=1 dots for small rolls
      expect(text, contains(',1,0,1,1,"TEST0001"'));
    });

    test('whole layout fits above the bottom edge', () {
      final image = img.Image(width: 240, height: 90);
      final bytes = buildTsplLabelBytes(
        nameImage: image,
        priceText: '1,000 Ks',
        barcodeValue: 'TEST0001',
        size: LabelSize.mm30x20,
      );
      final text = ascii.decode(bytes, allowInvalid: true);
      final m = barcodeCmd(text).firstMatch(text)!;
      final y = int.parse(m.group(2)!);
      final h = int.parse(m.group(3)!);
      expect(y + h, lessThanOrEqualTo(160 - 4));
    });

    test('large names cannot push the barcode off the label — the caller '
        'caps the bitmap, but the builder also stays sane if handed a tall '
        'one on the smallest roll', () {
      // A 30x20 roll with an absurd 150-dot-tall name: the builder must not
      // emit a negative-height or overflowing BARCODE.
      final image = img.Image(width: 240, height: 150);
      final bytes = buildTsplLabelBytes(
        nameImage: image,
        priceText: '1,000 Ks',
        barcodeValue: 'TEST0001',
        size: LabelSize.mm30x20,
      );
      final text = ascii.decode(bytes, allowInvalid: true);
      final m = barcodeCmd(text).firstMatch(text);
      if (m != null) {
        final y = int.parse(m.group(2)!);
        final h = int.parse(m.group(3)!);
        expect(h, greaterThan(0));
        expect(y + h, lessThanOrEqualTo(160));
      }
      // Either way the commands themselves stay well-formed.
      expect(text, contains('SIZE 30 mm,20 mm'));
    });

    test('big rolls keep the roomy 2-dot bars', () {
      final image = img.Image(width: 400, height: 100);
      final text = ascii.decode(
        buildTsplLabelBytes(
          nameImage: image,
          priceText: '1,000 Ks',
          barcodeValue: 'TEST0001',
          size: LabelSize.mm50x40,
        ),
        allowInvalid: true,
      );
      expect(text, contains(',1,0,2,2,"TEST0001"'));
    });
  });
}
