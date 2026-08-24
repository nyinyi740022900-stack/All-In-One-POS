// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Updates `<title>` and Open Graph / description meta tags for share previews
/// in browsers that execute JS (Telegram/in-app browsers). Facebook's crawler
/// still needs the Edge Function `?action=og` HTML card.
void updateStorefrontSeo({
  required String title,
  required String description,
  String? imageUrl,
  required String pageUrl,
}) {
  html.document.title = title;
  void setMeta(String attr, String key, String content) {
    var el = html.document.head?.querySelector('meta[$attr="$key"]');
    if (el == null) {
      el = html.MetaElement()..setAttribute(attr, key);
      html.document.head?.append(el);
    }
    el.setAttribute('content', content);
  }

  setMeta('name', 'description', description);
  setMeta('property', 'og:title', title);
  setMeta('property', 'og:description', description);
  setMeta('property', 'og:url', pageUrl);
  setMeta('property', 'og:type', 'website');
  if (imageUrl != null && imageUrl.isNotEmpty) {
    setMeta('property', 'og:image', imageUrl);
  }
}
