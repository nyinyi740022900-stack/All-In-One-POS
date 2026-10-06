import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/storefront/mmqr_checkout.dart';
import 'package:mm_pos/storefront/storefront_api.dart';

/// MyanMyanPay's compliance rules are a gate on taking money at all: an
/// application that breaks one does not pass review. They are therefore
/// asserted here rather than left to whoever next edits the widget.
void main() {
  MmqrOrder order({
    Duration remaining = const Duration(minutes: 15),
    int amount = 20000,
  }) => MmqrOrder(
    orderId: '8898fc6bd90241d587bc76756b5bd030',
    qr: '00020101021250790011MYANMYANPAY0124abc0232'
        '8898fc6bd90241d587bc76756b5bd0306304DD0C',
    amount: amount,
    expiresAt: DateTime.now().toUtc().add(remaining),
  );

  Future<void> pump(
    WidgetTester tester, {
    required MmqrOrder value,
    MmqrStatus status = MmqrStatus.pending,
    Locale locale = const Locale('en'),
    Future<void> Function()? onCancel,
    VoidCallback? onStartAgain,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(localeCode: locale.languageCode),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MmqrCheckout(
              order: value,
              status: status,
              busy: false,
              onCancel: onCancel ?? () async {},
              onStartAgain: onStartAgain ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The live surface runs a one-second countdown, so it never "settles" —
  /// pumpAndSettle would hang. Every step here pumps explicit frames.
  Future<void> openCancelDialog(WidgetTester tester) async {
    final button = find.widgetWithText(TextButton, 'Cancel this payment');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the required attribution string appears verbatim', (
    tester,
  ) async {
    await pump(tester, value: order());
    expect(find.text('PAYMENT POWERED BY MYANMYANPAY'), findsOneWidget);
  });

  testWidgets('the attribution is not translated in Myanmar either', (
    tester,
  ) async {
    // It is a brand requirement, not copy: translating it fails review.
    await pump(tester, value: order(), locale: const Locale('my'));
    expect(find.text('PAYMENT POWERED BY MYANMYANPAY'), findsOneWidget);
  });

  testWidgets('the MMQR logo is shown from the unaltered asset', (
    tester,
  ) async {
    await pump(tester, value: order());
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((a) => a.assetName)
        .toList();
    expect(images, contains('assets/branding/mmqr_logo.png'));
  });

  testWidgets('the EMVCo payload is rendered exactly as issued', (
    tester,
  ) async {
    final value = order();
    await pump(tester, value: value);
    final widget = tester.widget<BarcodeWidget>(find.byType(BarcodeWidget));
    // Not re-encoded, not prefixed, not trimmed — modifying the QR is
    // explicitly forbidden. BarcodeWidget keeps the payload as code units.
    expect(utf8.decode(widget.data), value.qr);
  });

  testWidgets('the price is MMK and no second currency sits beside it', (
    tester,
  ) async {
    await pump(tester, value: order());
    expect(find.text('20,000 MMK'), findsOneWidget);
    for (final symbol in ['SGD', 'USD', 'THB', 'JPY', r'$']) {
      expect(
        find.textContaining(symbol),
        findsNothing,
        reason: '$symbol must not appear on a live MMQR surface',
      );
    }
  });

  testWidgets('a visible countdown is shown and ticks down', (tester) async {
    await pump(
      tester,
      value: order(remaining: const Duration(minutes: 14, seconds: 40)),
    );
    expect(find.textContaining('14:'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('14:3'), findsOneWidget);
  });

  testWidgets('Download QR is offered while the order is live', (tester) async {
    await pump(tester, value: order());
    final button = find.widgetWithText(OutlinedButton, 'Download QR');
    expect(button, findsOneWidget);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('cancelling asks first, and keeping on waiting cancels nothing', (
    tester,
  ) async {
    var cancelled = false;
    await pump(
      tester,
      value: order(),
      onCancel: () async => cancelled = true,
    );
    await openCancelDialog(tester);
    expect(find.text('Cancel this payment?'), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(cancelled, isFalse);
  });

  testWidgets('confirming the dialog is what actually cancels', (tester) async {
    var cancelled = false;
    await pump(
      tester,
      value: order(),
      onCancel: () async => cancelled = true,
    );
    await openCancelDialog(tester);
    await tester.tap(find.text('Cancel payment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(cancelled, isTrue);
  });

  testWidgets('an expired window withdraws the code and offers a fresh one', (
    tester,
  ) async {
    var restarted = false;
    await pump(
      tester,
      value: order(remaining: Duration.zero),
      onStartAgain: () => restarted = true,
    );
    // The scannable code goes away with the window: a QR nobody should pay
    // must not stay on screen looking payable.
    expect(find.byType(BarcodeWidget), findsNothing);
    expect(find.text('PAYMENT POWERED BY MYANMYANPAY'), findsNothing);
    await tester.tap(find.text('Start again'));
    await tester.pump();
    expect(restarted, isTrue);
  });

  testWidgets('a paid order says so and offers no way to pay again', (
    tester,
  ) async {
    await pump(tester, value: order(), status: MmqrStatus.success);
    expect(find.text('Payment received. Premium is on.'), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsNothing);
    expect(find.text('Start again'), findsNothing);
  });

  testWidgets('a cancelled order can be started again', (tester) async {
    await pump(tester, value: order(), status: MmqrStatus.cancelled);
    expect(find.byType(BarcodeWidget), findsNothing);
    expect(find.text('Start again'), findsOneWidget);
  });

  group('MmqrStatus', () {
    test('maps MMPay\'s vocabulary, and anything unknown stays pending', () {
      expect(MmqrStatus.parse('SUCCESS'), MmqrStatus.success);
      expect(MmqrStatus.parse('CANCELLED'), MmqrStatus.cancelled);
      expect(MmqrStatus.parse('EXPIRED'), MmqrStatus.expired);
      expect(MmqrStatus.parse('FAILED'), MmqrStatus.failed);
      expect(MmqrStatus.parse('REFUNDED'), MmqrStatus.refunded);
      // A status we do not recognise must not be read as finished — the page
      // keeps waiting rather than telling the owner it is over.
      expect(MmqrStatus.parse('SOMETHING_NEW'), MmqrStatus.pending);
      expect(MmqrStatus.parse(null), MmqrStatus.pending);
    });

    test('REFUNDED is terminal but never releases the order as unpaid', () {
      // The money did arrive. Treating it as dead would offer a second QR for
      // a term that was already granted.
      expect(MmqrStatus.refunded.isDead, isFalse);
      expect(MmqrStatus.refunded.isPaid, isFalse);
      expect(MmqrStatus.failed.isDead, isTrue);
      expect(MmqrStatus.cancelled.isDead, isTrue);
      expect(MmqrStatus.expired.isDead, isTrue);
      expect(MmqrStatus.pending.isDead, isFalse);
    });
  });

  group('MmqrOrder', () {
    test('survives the round trip through the refresh cache', () {
      final value = order();
      final restored = MmqrOrder.fromMap(value.toJson());
      expect(restored.orderId, value.orderId);
      expect(restored.qr, value.qr);
      expect(restored.amount, value.amount);
      expect(restored.expiresAt, value.expiresAt);
    });

    test('a half-written cache entry is rejected rather than half-restored', () {
      final good = order().toJson();
      for (final missing in ['qr', 'order_id', 'expires_at']) {
        final broken = Map<String, dynamic>.from(good)..remove(missing);
        expect(
          () => MmqrOrder.fromMap(broken),
          throwsA(isA<FormatException>()),
          reason: missing,
        );
      }
    });

    test('a window that has already closed reports no time left, never negative', () {
      final past = MmqrOrder(
        orderId: 'a',
        qr: 'q',
        amount: 20000,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      expect(past.remaining(DateTime.now()), Duration.zero);
    });
  });
}
