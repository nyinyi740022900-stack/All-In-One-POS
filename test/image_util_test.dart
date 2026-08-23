import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mm_pos/core/image_util.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('compressImage (runs on a background isolate — audit C3)', () {
    /// A noisy photo-sized PNG — solid colours deflate to a few KB, which
    /// would trip the "JPEG came out larger, keep original" branch.
    Uint8List noisyPng(int width, int height) {
      final image = img.Image(width: width, height: height);
      var seed = 12345;
      for (final p in image) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p.r = seed & 0xff;
        p.g = (seed >> 8) & 0xff;
        p.b = (seed >> 16) & 0xff;
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('compresses an oversized photo to jpg within maxDim', () async {
      final input = noisyPng(2000, 1500);
      final r = await compressImage(input);

      expect(r.ext, 'jpg');
      final decoded = img.decodeJpg(r.bytes)!;
      expect(decoded.width, lessThanOrEqualTo(1280));
      expect(decoded.height, lessThanOrEqualTo(1280));
      expect(r.bytes.length, lessThan(input.length));
    });

    test('keeps an already-tiny image byte-identical (keep-original branch)',
        () async {
      final tiny = Uint8List.fromList(
          img.encodePng(img.Image(width: 40, height: 40)));
      final r = await compressImage(tiny, fallbackExt: 'png');

      expect(r.bytes, tiny);
      expect(r.ext, 'png');
    });

    test('undecodable bytes fall back to the original + fallbackExt',
        () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      final r = await compressImage(garbage, fallbackExt: 'jpg');

      expect(r.bytes, garbage);
      expect(r.ext, 'jpg');
    });
  });

  group('ProductThumb.cacheWidthFor (audit H2 decode budget)', () {
    test('scales the rendered side by device pixel ratio', () {
      expect(ProductThumb.cacheWidthFor(48, 3.0), 144);
      expect(ProductThumb.cacheWidthFor(118, 3.0), 354);
      expect(ProductThumb.cacheWidthFor(400, 2.0), 800);
    });

    test('never decodes below 96px or above 1024px', () {
      expect(ProductThumb.cacheWidthFor(20, 2.0), 96);
      expect(ProductThumb.cacheWidthFor(44, 1.0), 96);
      expect(ProductThumb.cacheWidthFor(2000, 2.0), 1024);
      expect(ProductThumb.cacheWidthFor(600, 3.0), 1024);
    });
  });
}
