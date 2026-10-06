import 'dart:async';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../l10n/app_localizations.dart';
import 'browser_actions_stub.dart'
    if (dart.library.js_interop) 'storefront_download.dart';
import 'storefront_api.dart';

/// The MMQR payment surface, and the only place in this app that renders one.
///
/// MyanMyanPay's compliance rules are not style suggestions — an application
/// that breaks them does not pass review and therefore cannot take money. Each
/// one is implemented here and named where it is:
///
///   * the MMQR logo, shown unaltered from `assets/branding/mmqr_logo.png`;
///   * MMK only, never a second currency beside it;
///   * the verbatim string "PAYMENT POWERED BY MYANMYANPAY" beneath the code;
///   * the EMVCo payload rendered exactly as issued, never modified;
///   * a visible fifteen-minute timer;
///   * a working Download QR button;
///   * no second order while one is live unless the owner cancels this one.
///
/// Refresh-safety (the order surviving a return from the banking app) lives in
/// the page that owns this widget, because the cache must be read before the
/// first frame, not after.
class MmqrCheckout extends StatefulWidget {
  const MmqrCheckout({
    super.key,
    required this.order,
    required this.status,
    required this.busy,
    required this.onCancel,
    required this.onStartAgain,
  });

  final MmqrOrder order;

  /// What the server last heard from MMPay. The page polls; this widget only
  /// renders — it never decides on its own that an order is finished.
  final MmqrStatus status;
  final bool busy;
  final Future<void> Function() onCancel;
  final VoidCallback onStartAgain;

  @override
  State<MmqrCheckout> createState() => _MmqrCheckoutState();
}

class _MmqrCheckoutState extends State<MmqrCheckout> {
  Timer? _tick;
  final _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // The compliance rules require a *visible* countdown, so it ticks on its
    // own rather than only when a poll happens to return.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _remaining => widget.order.remaining(DateTime.now());

  bool get _finished => widget.status.isPaid || widget.status.isDead;

  /// Our own fifteen-minute window, not MMPay's — they publish no TTL. When it
  /// runs out the page stops offering the code, but the server's status stays
  /// the authority on whether the order is actually dead, so a late payment is
  /// still reconciled rather than lost.
  bool get _windowClosed => _remaining == Duration.zero;

  Future<void> _download() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Rasterised from the very widget on screen, so what is saved is the
      // same unmodified EMVCo code the owner is looking at.
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await saveImageToPhotos(
        data.buffer.asUint8List(),
        'mmqr-${widget.order.orderId}.png',
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l.storefrontRenewMmqrDownloaded)),
      );
    } catch (_) {
      // A refused share sheet or a browser without it is not an error worth
      // interrupting a payment for; the code is still on screen to scan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Unaltered, and never recoloured or cropped: MMPay's first rule.
            Image.asset(
              'assets/branding/mmqr_logo.png',
              height: 56,
              fit: BoxFit.contain,
              semanticLabel: 'MMQR',
            ),
            const SizedBox(height: AppTheme.space3),
            if (widget.status.isPaid)
              _Outcome(
                icon: Icons.check_circle,
                color: theme.colorScheme.primary,
                title: l.storefrontRenewMmqrPaid,
                body: l.storefrontRenewMmqrPaidBody,
              )
            else if (widget.status == MmqrStatus.cancelled)
              _Outcome(
                icon: Icons.cancel_outlined,
                color: theme.colorScheme.outline,
                title: l.storefrontRenewMmqrCancelled,
                onAction: widget.onStartAgain,
                actionLabel: l.storefrontRenewMmqrStartAgain,
              )
            else if (widget.status.isDead || _windowClosed)
              _Outcome(
                icon: Icons.timer_off_outlined,
                color: theme.colorScheme.outline,
                title: widget.status == MmqrStatus.failed
                    ? l.storefrontRenewMmqrFailed
                    : l.storefrontRenewMmqrExpired,
                onAction: widget.onStartAgain,
                actionLabel: l.storefrontRenewMmqrStartAgain,
              )
            else
              ..._live(context, l),
          ],
        ),
      ),
    );
  }

  List<Widget> _live(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    return [
      Text(
        // MMK and nothing else. The card option is hidden by the page while a
        // QR is live precisely so no other currency can sit beside this.
        l.storefrontRenewMmqrAmount(_groupedAmount),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: AppTheme.space1),
      Text(
        l.storefrontRenewMmqrScanHint,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppTheme.space3),
      Center(
        child: RepaintBoundary(
          key: _qrKey,
          child: Container(
            padding: const EdgeInsets.all(AppTheme.space3),
            color: Colors.white,
            child: BarcodeWidget(
              // The EMVCo payload exactly as MMPay issued it. Modifying a QR
              // is explicitly forbidden, so nothing is appended or re-encoded.
              data: widget.order.qr,
              barcode: Barcode.qrCode(),
              width: 240,
              height: 240,
              color: Colors.black,
              backgroundColor: Colors.white,
              drawText: false,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppTheme.space2),
      Text(
        // Verbatim, in this exact wording. Not translated, not re-cased.
        l.storefrontRenewMmqrPoweredBy,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppTheme.space3),
      _Countdown(remaining: _remaining, label: l.storefrontRenewMmqrExpiresIn),
      const SizedBox(height: AppTheme.space2),
      Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              l.storefrontRenewMmqrWaiting,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.space1),
      Text(
        l.storefrontRenewMmqrRefreshSafe,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppTheme.space3),
      OutlinedButton.icon(
        onPressed: _finished ? null : _download,
        icon: const Icon(Icons.download),
        label: Text(l.storefrontRenewMmqrDownload),
      ),
      const SizedBox(height: AppTheme.space2),
      // MMPay forbids issuing a second order while one is live unless the
      // owner explicitly cancels — so this has to be a real cancel, and it
      // asks first because cancelling after paying is the costly mistake.
      TextButton(
        onPressed: widget.busy ? null : _confirmCancel,
        child: widget.busy
            ? const ButtonSpinner()
            : Text(l.storefrontRenewMmqrCancel),
      ),
    ];
  }

  String get _groupedAmount {
    final digits = widget.order.amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  Future<void> _confirmCancel() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.storefrontRenewMmqrCancelTitle),
        content: Text(l.storefrontRenewMmqrCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.storefrontRenewMmqrCancelKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.storefrontRenewMmqrCancelConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onCancel();
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining, required this.label});

  final Duration remaining;
  final String Function(String) label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final text = '$minutes:${seconds.toString().padLeft(2, '0')}';
    // Under two minutes the countdown turns into a warning rather than an
    // ornament, because that is when starting again is still cheap.
    final urgent = remaining.inSeconds <= 120;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space2,
      ),
      decoration: BoxDecoration(
        color: urgent
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 18,
            color: urgent ? theme.colorScheme.onErrorContainer : null,
          ),
          const SizedBox(width: AppTheme.space2),
          Text(
            label(text),
            style: theme.textTheme.titleSmall?.copyWith(
              color: urgent ? theme.colorScheme.onErrorContainer : null,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.color,
    required this.title,
    this.body,
    this.onAction,
    this.actionLabel,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 40, color: color),
        const SizedBox(height: AppTheme.space2),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (body != null) ...[
          const SizedBox(height: AppTheme.space1),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (onAction != null) ...[
          const SizedBox(height: AppTheme.space3),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}
