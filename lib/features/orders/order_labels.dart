import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Localized label for an order pipeline status code.
String orderStatusLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'delivered':
      return l.orderStatusDelivered;
    case 'cancelled':
      return l.orderStatusCancelled;
    case 'new':
    default:
      return l.orderStatusNew;
  }
}

/// A distinct accent colour per status (filter chips + card stripes).
Color orderStatusColor(String status) {
  switch (status) {
    case 'delivered':
      return const Color(0xFF10B981); // green
    case 'cancelled':
      return const Color(0xFF9CA3AF); // grey
    case 'new':
    default:
      return const Color(0xFF64748B); // slate
  }
}

/// Localized label for a social channel code. `storefront` is the shop's own
/// web catalog (an order the customer placed directly, not via a social
/// message) — it must be handled explicitly here, or it silently falls
/// through to the `facebook` label below.
String orderChannelLabel(AppLocalizations l, String channel) {
  switch (channel) {
    case 'viber':
      return l.orderChannelViber;
    case 'tiktok':
      return l.orderChannelTiktok;
    case 'phone':
      return l.orderChannelPhone;
    case 'storefront':
      return l.orderChannelStorefront;
    case 'other':
      return l.orderChannelOther;
    case 'facebook':
    default:
      return l.orderChannelFacebook;
  }
}

IconData orderChannelIcon(String channel) {
  switch (channel) {
    case 'phone':
      return Icons.phone;
    case 'storefront':
      return Icons.language;
    case 'viber':
    case 'tiktok':
    case 'facebook':
    case 'other':
    default:
      return Icons.chat_bubble_outline;
  }
}

/// Localized label for a payment status code. Order.paymentStatus is only
/// ever written as 'paid' or 'unpaid' (setPaymentStatus, convertToSale, the
/// storefront submit_order function) — there's no 'partial' state to label.
String orderPaymentLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'paid':
      return l.orderPayPaid;
    case 'unpaid':
    default:
      return l.orderPayUnpaid;
  }
}
