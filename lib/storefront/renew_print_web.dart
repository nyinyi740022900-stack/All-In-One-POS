import 'package:web/web.dart' as web;

/// Hands the receipt to the browser's own print dialog — which on every
/// desktop and mobile browser also offers "Save as PDF", so a shop can keep
/// the receipt for its books without us generating a document.
///
/// Web-only, like [saveImageToPhotos] in `storefront_download.dart`: this
/// file is only ever compiled into the storefront web entrypoint, never the
/// mobile app.
void printCurrentPage() => web.window.print();
