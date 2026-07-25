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
}
