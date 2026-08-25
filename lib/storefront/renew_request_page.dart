import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/image_util.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../l10n/app_localizations.dart';
import 'renewal_receipt_view.dart';
import 'storefront_api.dart';
import 'storefront_page.dart' show StorefrontLocaleBar;

final _money = NumberFormat('#,##0', 'en_US');
String _ks(AppLocalizations l, int v) => '${_money.format(v)} ${l.currencySymbol}';

/// Subscription-renewal request form at `/renew` — restores a live path
/// into `license_requests` now that the in-app payment UI is gone (removed
/// for App Store 5.1.1(v) compliance; a web page isn't subject to that
/// rule). Owner-facing and shop-agnostic: identified only by the device_id
/// ("App Reference ID") the owner types in, unlike every other page in
/// `lib/storefront/`, which is customer-facing and addressed by a shop
/// slug. Kept in its own file rather than folded into `storefront_page.dart`
/// for exactly that reason.
class RenewRequestPage extends StatefulWidget {
  const RenewRequestPage({
    super.key,
    required this.locale,
    required this.onToggleLocale,
  });
  final Locale locale;
  final VoidCallback onToggleLocale;

  @override
  State<RenewRequestPage> createState() => _RenewRequestPageState();
}

class _RenewRequestPageState extends State<RenewRequestPage> {
  // 5 years — comfortably covers any real renewal request while guarding
  // against a fat-fingered huge month count silently computing (and
  // locking in, via [_amountLocked]) an arbitrarily large Amount with no
  // warning before submit.
  static const int _maxMonths = 60;

  final _api = StorefrontApi();
  late final Future<Map<String, String>> _paymentConfig;

  final _shopName = TextEditingController();
  final _deviceId = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _refNo = TextEditingController();
  final _months = TextEditingController(text: '1');
  // Honeypot — same convention as storefront_page.dart's _CheckoutSheet:
  // real users never see or fill this; a scripted bot blindly filling every
  // input will. Checked server-side.
  final _hp = TextEditingController();

  String _plan = 'monthly';
  String _method = 'kbzpay';
  bool _submitting = false;
  bool _submitted = false;
  String? _requestId;
  String? _invoiceNo;
  List<int>? _proofBytes;
  String? _proofExt;
  String? _proofName;

  // Admin-configured price.monthly/price.yearly, once loaded — drives both
  // the per-unit price shown next to the Plan toggle and the auto-filled
  // Amount below. No online/offline split here (unlike VendorConfig's own
  // tier-aware priceFor): this app no longer distinguishes an online vs.
  // offline plan, so a single admin-set rate applies to every request.
  int? _priceMonthly;
  int? _priceYearly;

  @override
  void initState() {
    super.initState();
    _paymentConfig = _api.fetchPaymentConfig();
    _paymentConfig.then((cfg) {
      if (!mounted) return;
      setState(() {
        _priceMonthly = int.tryParse(cfg['price.monthly'] ?? '');
        _priceYearly = int.tryParse(cfg['price.yearly'] ?? '');
      });
      _recalcAmount();
    });
    // The app's own "Pay online" link passes along what it already knows
    // (LicenseScreen._openRenewPage) so a shop opening this from Settings
    // doesn't have to retype its own name/App Reference ID/email. Plain
    // query params — nothing here is sensitive, and this same data is
    // already visible in the form itself once filled in.
    final q = Uri.base.queryParameters;
    // `/renew?receipt=<id>` reopens an existing request's receipt instead of
    // the form — the shop saved this link (or we sent it on Viber) and wants
    // to know where its payment got to.
    final receipt = (q['receipt'] ?? '').trim();
    if (receipt.isNotEmpty) {
      _submitted = true;
      _requestId = receipt;
    }
    _shopName.text = q['name'] ?? '';
    _deviceId.text = q['device_id'] ?? '';
    _email.text = q['email'] ?? '';
    _months.addListener(_recalcAmount);
  }

  /// The price per month/year is admin-fixed, not negotiable — so unlike a
  /// storefront cart, this is the exact amount owed, not a suggestion the
  /// owner can override (see [_amountLocked]). Yearly rounds the month
  /// count up to the nearest whole year so a mid-year top-up (e.g. 18
  /// months) still charges a sane amount rather than under-charging.
  void _recalcAmount() {
    final rawMonths = int.tryParse(_months.text.trim()) ?? 0;
    final months = rawMonths > _maxMonths ? _maxMonths : rawMonths;
    if (months <= 0) return;
    final int? total;
    if (_plan == 'yearly' && _priceYearly != null) {
      total = _priceYearly! * ((months + 11) ~/ 12);
    } else if (_plan == 'monthly' && _priceMonthly != null) {
      total = _priceMonthly! * months;
    } else {
      total = null;
    }
    if (total != null) {
      _amount.text = '$total';
    }
  }

  /// True once the admin-configured price for the selected plan is known —
  /// at that point Amount is locked (read-only, exact) rather than a plain
  /// field, since there's a fixed rate to charge against. Falls back to a
  /// plain editable field if the price genuinely failed to load (a config
  /// fetch error, or an admin who hasn't set one yet) — better than
  /// blocking the whole form on a config read that never resolves.
  bool get _amountLocked =>
      (_plan == 'yearly' ? _priceYearly : _priceMonthly) != null;

  @override
  void dispose() {
    _shopName.dispose();
    _deviceId.dispose();
    _email.dispose();
    _phone.dispose();
    _amount.dispose();
    _refNo.dispose();
    _months.dispose();
    _hp.dispose();
    super.dispose();
  }

  void _onPlanChanged(String plan) {
    setState(() {
      _plan = plan;
      _months.text = plan == 'yearly' ? '12' : '1';
    });
  }

  Future<void> _pickProof() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    final c = await compressImage(Uint8List.fromList(file.bytes!),
        fallbackExt: (file.extension ?? 'jpg').toLowerCase());
    setState(() {
      _proofBytes = c.bytes;
      _proofExt = c.ext;
      _proofName = file.name;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final shopName = _shopName.text.trim();
    final deviceId = _deviceId.text.trim();
    final email = _email.text.trim();
    final months = int.tryParse(_months.text.trim()) ?? 0;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final refNo = _refNo.text.trim();
    if (months > _maxMonths) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storefrontRenewMonthsTooHigh)),
      );
      return;
    }
    if (shopName.isEmpty ||
        (deviceId.isEmpty && email.isEmpty) ||
        months <= 0 ||
        amount <= 0 ||
        refNo.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.storefrontRenewMissingFields)),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      String? proofPath;
      if (_proofBytes != null) {
        // Renew proofs are admin-review-only — the `_admin/` folder is the
        // one bucket folder no shop session can read (migration 0066).
        proofPath = await _api.uploadPaymentProof(
          _proofBytes!,
          _proofExt ?? 'jpg',
          folder: '_admin',
        );
      }
      final submitted = await _api.submitLicenseRequest(
        shopName: shopName,
        deviceId: deviceId,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        plan: _plan,
        months: months,
        method: _method,
        amount: amount,
        refNo: refNo,
        paymentProofPath: proofPath,
        hp: _hp.text,
      );
      if (mounted) {
        setState(() {
          _submitted = true;
          _requestId = submitted.requestId.isEmpty ? null : submitted.requestId;
          _invoiceNo = submitted.invoiceNo;
        });
      }
    } catch (e) {
      if (mounted) {
        final raw = '$e';
        final message = raw.contains('rate_limited')
            ? l.storefrontRenewRateLimited
            : l.storefrontRenewFailed;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: StorefrontLocaleBar(
          locale: widget.locale, onToggle: widget.onToggleLocale),
      body: _submitted ? _afterSubmit(l) : _form(l),
    );
  }

  Widget _afterSubmit(AppLocalizations l) {
    final id = _requestId;
    // The receipt IS the confirmation — it says the same "we got it" and
    // then keeps saying something useful every time the shop comes back.
    if (id != null) {
      return RenewalReceiptView(requestId: id, initialInvoiceNo: _invoiceNo);
    }
    // Only reachable if the server accepted the request but returned no id
    // (it always returns one today). Never leave the shop staring at a form
    // it already submitted.
    return _confirmationFallback(l);
  }

  Widget _confirmationFallback(AppLocalizations l) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: AppColors.of(context).success, size: 48),
            const SizedBox(height: AppTheme.space3),
            Text(l.storefrontRenewSubmitted,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.storefrontRenewTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppTheme.space2),
          Text(l.storefrontRenewHint,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppTheme.space4),
          // Honeypot — kept out of the visible layout entirely (zero size),
          // so no real user can tab/scroll into it.
          Offstage(child: TextField(controller: _hp, autofocus: false)),
          TextField(
            controller: _shopName,
            decoration: InputDecoration(labelText: l.storefrontRenewShopName),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _deviceId,
            decoration: InputDecoration(
              labelText: l.licenseRefId,
              helperText: l.storefrontRenewDeviceIdHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l.storefrontRenewEmail,
              helperText: l.storefrontRenewEmailHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.shopPhone),
          ),
          const SizedBox(height: AppTheme.space4),
          SectionHeader(title: l.storefrontRenewPlan),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'monthly', label: Text(l.licensePlanMonthly)),
              ButtonSegment(value: 'yearly', label: Text(l.licensePlanYearly)),
            ],
            selected: {_plan},
            onSelectionChanged: (s) => _onPlanChanged(s.first),
          ),
          Builder(builder: (context) {
            final price = _plan == 'yearly' ? _priceYearly : _priceMonthly;
            if (price == null) return const SizedBox.shrink();
            final text = _plan == 'yearly'
                ? l.storefrontRenewPricePerYear(_ks(l, price))
                : l.storefrontRenewPricePerMonth(_ks(l, price));
            return Padding(
              padding: const EdgeInsets.only(top: AppTheme.space1),
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            );
          }),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(labelText: l.storefrontRenewMonths),
          ),
          const SizedBox(height: AppTheme.space4),
          SectionHeader(title: l.storefrontPayment),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'kbzpay', label: Text('KBZPay')),
              ButtonSegment(value: 'wavepay', label: Text('WavePay')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: AppTheme.space3),
          FutureBuilder<Map<String, String>>(
            future: _paymentConfig,
            builder: (context, snap) {
              final cfg = snap.data;
              if (cfg == null) return const SizedBox.shrink();
              final name = _method == 'kbzpay'
                  ? cfg['pay.kbzpay.name']
                  : cfg['pay.wavepay.name'];
              final number = _method == 'kbzpay'
                  ? cfg['pay.kbzpay.number']
                  : cfg['pay.wavepay.number'];
              if ((number ?? '').isEmpty) return const SizedBox.shrink();
              return Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: Row(
                    children: [
                      Text(l.storefrontPayTo),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: Text(
                          (name ?? '').isEmpty ? number! : '$name · $number',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: l.storefrontCopyNumber,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: number!));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(l.storefrontNumberCopied)));
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _amount,
            readOnly: _amountLocked,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l.storefrontRenewAmountPaid,
              helperText: _amountLocked
                  ? l.storefrontRenewAmountLockedHint
                  : null,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _refNo,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: l.storefrontRenewRefNo,
              helperText: l.storefrontRenewRefNoHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          OutlinedButton.icon(
            onPressed: _pickProof,
            icon: const Icon(Icons.upload_file),
            label: Text(_proofName == null
                ? l.storefrontAttachProof
                : l.storefrontProofAttached(_proofName!)),
          ),
          const SizedBox(height: AppTheme.space5),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space2),
              child: _submitting
                  ? const ButtonSpinner()
                  : Text(l.storefrontRenewSubmit),
            ),
          ),
        ],
      ),
    );
  }
}
