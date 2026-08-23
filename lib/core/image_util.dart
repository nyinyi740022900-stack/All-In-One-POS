import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Downscales + re-encodes an image to keep uploads small (payment screenshots
/// and product/logo photos are often several MB straight from a phone camera).
///
/// Decodes [input], resizes so the longest edge is at most [maxDim], and
/// re-encodes as JPEG at [quality]. Returns `(bytes, 'jpg')`. If decoding
/// fails (unknown format), returns the original bytes + [fallbackExt] so the
/// upload still succeeds — never blocks the user over a compression miss.
///
/// The decode/resize/encode pipeline is pure-Dart CPU work (`package:image`)
/// that used to run inline on the UI isolate — picking a product photo or a
/// payment proof froze every frame for seconds on a multi-MB camera shot
/// (audit C3). It now runs on a background isolate via [compute]; on Flutter
/// web (storefront guests) `compute` degrades to the main thread, so the web
/// path keeps its old behaviour rather than breaking.
Future<({Uint8List bytes, String ext})> compressImage(
  Uint8List input, {
  String fallbackExt = 'jpg',
  int maxDim = 1280,
  int quality = 78,
}) {
  return compute(_compressImageSync, (input, fallbackExt, maxDim, quality));
}

/// Synchronous worker behind [compressImage] — a top-level function so
/// [compute] can send it across the isolate boundary.
({Uint8List bytes, String ext}) _compressImageSync(
  (Uint8List, String, int, int) args,
) {
  final (input, fallbackExt, maxDim, quality) = args;
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return (bytes: input, ext: fallbackExt);
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest > maxDim
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxDim : null,
            height: decoded.height > decoded.width ? maxDim : null,
          )
        : decoded;
    final jpg = img.encodeJpg(resized, quality: quality);
    // If somehow larger than the original (already-small PNG icon), keep original.
    if (jpg.length >= input.length) return (bytes: input, ext: fallbackExt);
    return (bytes: jpg, ext: 'jpg');
  } catch (_) {
    return (bytes: input, ext: fallbackExt);
  }
}
