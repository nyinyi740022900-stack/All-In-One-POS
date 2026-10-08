import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'mmqr_checkout.dart';
import 'storefront_api.dart';

/// A public, account-free rendering of the MMQR checkout surface, reserved at
/// `/mmqr-preview`.
///
/// It exists for one reason: MyanMyanPay's compliance review needs to see the
/// surface, and the real one lives behind an owner sign-in on `/renew` *and*
/// behind MMQR being configured — which does not happen until the application
/// is approved. Without this page the review is circular.
///
/// Everything below the banner is the same [MmqrCheckout] widget the owner
/// sees, with no review-only styling: a preview that differed from the real
/// thing would be worse than no preview at all. The payload is a genuine,
/// unmodified MMQR issued by MyanMyanPay's sandbox for a test order that was
/// afterwards cancelled, so it cannot take money from anyone who scans it.
class MmqrPreviewPage extends StatelessWidget {
  const MmqrPreviewPage({
    super.key,
    required this.locale,
    required this.onToggleLocale,
  });

  final Locale locale;
  final VoidCallback onToggleLocale;

  /// Issued by MyanMyanPay's sandbox (app MM57179826) and cancelled. Rendered
  /// exactly as received — not re-encoded, not trimmed, nothing appended.
  static const _sampleQr =
      '00020101021250790011MYANMYANPAY01246a8cf24821ac00fe98bf387a0232'
      'c5dbb762b8a140b5aa24fc73ceec93265204481253031045405200005802MM'
      '5911MyanMyanPay6006YANGON62360132c5dbb762b8a140b5aa24fc73ceec93'
      '2663047442';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A fixed future expiry, so the countdown is always mid-window for a
    // reviewer arriving at any time of day.
    final order = MmqrOrder(
      orderId: 'c5dbb762b8a140b5aa24fc73ceec9326',
      qr: _sampleQr,
      amount: 20000,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 14)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('MMQR compliance preview'),
        actions: [
          TextButton(
            onPressed: onToggleLocale,
            child: Text(locale.languageCode == 'my' ? 'EN' : 'မြန်မာ'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.space3),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.space3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This is a preview, not a live order',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppTheme.space2),
                        Text(
                          'App MM57179826 · All In One POS. The owner normally '
                          'reaches this surface at /renew after signing in to '
                          'their shop account, which is why it is not visible '
                          'from the public site. The code below is a real '
                          'sandbox MMQR that was cancelled after testing, so '
                          'scanning it cannot take money.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.space3),
                MmqrCheckout(
                  order: order,
                  status: MmqrStatus.pending,
                  busy: false,
                  onCancel: () async {},
                  onStartAgain: () {},
                ),
                const SizedBox(height: AppTheme.space4),
                _Rules(theme: theme),
                const SizedBox(height: AppTheme.space4),
                _Flow(theme: theme),
                const SizedBox(height: AppTheme.space4),
                Text(
                  'The surface is bilingual — use the button in the title bar '
                  'to see it in ${locale.languageCode == 'my' ? 'English' : 'Myanmar'}. '
                  'The attribution line beneath the code stays in English in '
                  'both, because it is a brand requirement and not copy.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.theme});
  final ThemeData theme;

  static const _rules = <(String, String)>[
    (
      'MMQR logo, unaltered',
      'Shown above the code from the supplied asset. Never recoloured, '
          'cropped or rebuilt.',
    ),
    (
      'MMK only',
      'The price reads "20,000 MMK". No second currency appears anywhere on '
          'the surface, and the card-payment option is hidden while a QR is '
          'live so none can appear beside it.',
    ),
    (
      'PAYMENT POWERED BY MYANMYANPAY',
      'Printed verbatim beneath the code, in that exact wording and casing, '
          'in both languages.',
    ),
    (
      'The EMVCo payload is unmodified',
      'Rendered exactly as issued — not re-encoded, trimmed or prefixed.',
    ),
    (
      'A visible 15-minute timer',
      'Counts down once per second on its own, and turns into a warning under '
          'two minutes. When it reaches zero the code is withdrawn rather than '
          'left on screen looking payable.',
    ),
    (
      'Download QR works',
      'Saves the code exactly as displayed, rasterised from the widget on '
          'screen.',
    ),
    (
      'One live order at a time',
      'A second order cannot be issued while one is live unless the owner '
          'cancels this one, which asks for confirmation first and re-queries '
          'the order before closing it — so cancelling something that was in '
          'fact paid fulfils it instead of throwing the payment away.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compliance rules', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppTheme.space2),
          for (final (title, body) in _rules) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space1),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(body, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Flow extends StatelessWidget {
  const _Flow({required this.theme});
  final ThemeData theme;

  static const _steps = <String>[
    'The shop owner signs in to their own account and opens /renew, picks '
        'monthly (20,000 MMK) or yearly (200,000 MMK), and chooses MMQR.',
    'Our server reserves the checkout, calls POST /payments/pay, and shows '
        'the returned MMQR exactly as issued. The order id is the checkout '
        'row id compacted to the 32 characters MMPay allows.',
    'The page polls GET /payments/get. The callback to our webhook is treated '
        'only as a hint — every grant re-queries MyanMyanPay, so a lost or '
        'delayed callback never costs the owner the month they paid for, and '
        'a forged one grants nothing.',
    'On SUCCESS the subscription is extended by exactly the term that was '
        'bought. The price is re-derived from the stored term rather than '
        'trusted from the request, repeat confirmations are idempotent, and a '
        'refund is recorded without clawing the term back mid-trading.',
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How the live flow works', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppTheme.space2),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
