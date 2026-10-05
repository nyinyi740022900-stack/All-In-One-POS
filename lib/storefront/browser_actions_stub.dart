import 'dart:typed_data';

// Keep browser-only printing and downloads out of native widget-test imports.
void printCurrentPage() => throw UnsupportedError('Browser printing only');
Future<void> saveImageToPhotos(Uint8List bytes, String filename) async =>
    throw UnsupportedError('Browser downloads only');
