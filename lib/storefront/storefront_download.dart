import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Offers [bytes] to the customer as a saved photo, not an anonymous file in
/// Downloads. Web-only — this file is only ever compiled as part of the
/// storefront web entrypoint, never the mobile app.
///
/// Primary path: the Web Share API's native share sheet — on iOS Safari /
/// Android Chrome this includes a direct **"Save Image" / "Save to Photos"**
/// action, which is exactly what a Save button should feel like on mobile.
/// Falls back to opening the image in a new tab (a real `<img>`, since
/// Flutter web paints to canvas) when the browser can't share files — from
/// there, long-press → Save Image works the same way.
Future<void> saveImageToPhotos(Uint8List bytes, String filename) async {
  final file = web.File(
    [bytes.toJS].toJS,
    filename,
    web.FilePropertyBag(type: 'image/png'),
  );
  final data = web.ShareData(files: [file].toJS);

  if (web.window.navigator.canShare(data)) {
    try {
      await web.window.navigator.share(data).toDart;
      return;
    } catch (_) {
      // User cancelled the share sheet, or the browser refused after all —
      // fall through to the new-tab fallback below.
    }
  }

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}
