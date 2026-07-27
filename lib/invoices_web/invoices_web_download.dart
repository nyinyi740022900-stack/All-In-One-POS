import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a standard browser file download (not a share sheet — a desktop
/// visitor expects a normal Save-to-Downloads, unlike the storefront's
/// mobile-oriented `saveImageToPhotos`). Web-only, like the storefront's own
/// download helper — never compiled into the mobile app.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
