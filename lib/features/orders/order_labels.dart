import 'package:flutter/material.dart';

import '../../core/widgets/app_widgets.dart';
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

/// The semantic weight of an order pipeline status, for [StatusPill].
///
/// This used to return three raw hex colours (`#10B981` green, `#9CA3AF`
/// grey, `#64748B` slate) picked before the app had a palette — a Tailwind
/// emerald that sat right on top of the brand green, and two greys with no
/// relationship to the surface ramp. Returning a *tone* instead of a
/// [Color] means the two places that render an order's status (the list card
/// and the detail sheet) can't drift apart, and dark mode is handled by the
/// palette rather than by an alpha wash over near-black.
///
/// `new` is [StatusTone.attention], not neutral: an order sitting in `new` is
/// the shop's to-do list — it is waiting on someone to hand it to a carrier.
/// `cancelled` is [StatusTone.neutral], not danger: a cancelled order is
/// finished-with, not an error to chase, and a list of red rows for the
/// normal end-state of returns trains the eye to ignore red.
StatusTone orderStatusTone(String status) => switch (status) {
  'delivered' => StatusTone.positive,
  'cancelled' => StatusTone.neutral,
  _ => StatusTone.attention,
};

/// Tone for an order's payment status — anything short of fully paid
/// (including `partial`, see [orderPaymentLabel]) reads as attention.
StatusTone orderPaymentTone(String status) =>
    status == 'paid' ? StatusTone.positive : StatusTone.attention;

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

/// Localized label for a payment status code. `setPaymentStatus`, the
/// storefront `submit_order` function, and a fresh order all only ever write
/// 'paid' or 'unpaid' — but `convertToSale` also writes 'partial' when the
/// amount collected at conversion is more than zero and less than the total,
/// so that state must be labeled explicitly rather than falling through to
/// "Unpaid" for an order that actually collected some payment. Shares
/// `invoiceStatusPartial`'s wording with the Invoices ledger's own
/// paid/partial/unpaid labeling for the same underlying concept.
String orderPaymentLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'paid':
      return l.orderPayPaid;
    case 'partial':
      return l.invoiceStatusPartial;
    case 'unpaid':
    default:
      return l.orderPayUnpaid;
  }
}
