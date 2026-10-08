import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../core/image_util.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/support/viber_launch.dart';
import '../l10n/app_localizations.dart';
import 'mmqr_checkout.dart';
import 'mmqr_store_stub.dart'
    if (dart.library.js_interop) 'mmqr_store_web.dart';
import 'renewal_auth.dart';
import 'renewal_receipt_view.dart';
import 'storefront_api.dart';
import 'storefront_page.dart' show StorefrontLocaleBar;

final _money = NumberFormat('#,##0', 'en_US');
String _ks(AppLocalizations l, int v) =>
    '${_money.format(v)} ${l.currencySymbol}';

/// Owner-authenticated purchase and renewal for an explicitly selected shop.
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
  final _api = StorefrontApi();
  final _auth = RenewalAuth();
  StreamSubscription<AuthState>? _authSubscription;
  String? _authAccountId;
  String? _preparedAccountId;
  int _accountGeneration = 0;
  late final Future<Map<String, String>> _paymentConfig;

  List<Map<String, dynamic>>? _shops;
  String? _shopId;

  /// Whether the server can take an international card payment. Stays false
  /// until it says otherwise, so the card option is never offered on a
  /// project without a configured processor.
  bool _cardPayment = false;
  bool _openingCheckout = false;

  /// Whether the server can issue an MMQR. Same rule as [_cardPayment]:
  /// false until it says otherwise.
  bool _mmqrPayment = false;

  /// The selected shop's live card subscription, when it has one. Null means
  /// nothing to manage — which is also what a processor we cannot reach looks
  /// like, so a status panel never blocks the page's real job of selling a
  /// term.
  CardSubscription? _cardSubscription;

  /// The live order, if any. While this is non-null the card option is hidden:
  /// MMPay forbids any other currency sharing the surface with a live MMQR.
  MmqrOrder? _mmqrOrder;
  MmqrStatus _mmqrStatus = MmqrStatus.pending;
  bool _mmqrBusy = false;
  Timer? _mmqrPoll;
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _refNo = TextEditingController();
  final _months = TextEditingController(text: '1');
  // Honeypot — same convention as storefront_page.dart's _CheckoutSheet:
  // real users never see or fill this; a scripted bot blindly filling every
  // input will. Checked server-side.
  final _hp = TextEditingController();

  // Billing authenticates the owner without claiming a POS device slot.
  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  bool _signingIn = false;
  String? _signInError;
  List<RenewalRequestSummary>? _myRequests;
  bool _loadingHistory = false;

  /// `null` = not chosen yet, `'mm'` = Myanmar, `'intl'` = international.
  /// Determines which payment options are visible: Myanmar shows MMQR +
  /// manual local transfer; international shows the Lemon Squeezy card path.
  String? _region;

  String _plan = 'monthly';
  String _method = 'kbzpay';
  bool _submitting = false;
  bool _submitted = false;

  /// Generated once and reused across retries so a lost response cannot
  /// become a second paid renewal request. See StorefrontApi.
  String? _clientRequestId;
  String? _requestId;
  String? _invoiceNo;
  List<int>? _proofBytes;
  String? _proofExt;
  String? _proofName;

  // Myanmar prices (Kyat) — fixed, independently enforced by the server.
  final int _priceMonthlyMmk = 20000;
  final int _priceYearlyMmk = 200000;

  // International prices (SGD cents) — Lemon Squeezy handles the charge.
  final int _priceMonthlyIntl = 499; // SGD 4.99
  final int _priceYearlyIntl = 4990; // SGD 49.90

  // Shown both on the form and on the receipt right after submitting — the
  // moment a shop is most anxious to hear back is exactly while its request
  // sits "pending", so that's where an urgent-escalation path matters most,
  // not buried back in Settings.
  String? _supportViber;

  @override
  void initState() {
    super.initState();
    _paymentConfig = _api.fetchPaymentConfig();
    _paymentConfig.then(
      (cfg) {
        if (!mounted) return;
        setState(() {
          _supportViber = cfg['support.viber'];
        });
        _recalcAmount();
      },
      onError: (_) {
        // The FutureBuilder below renders its own error state; this second
        // listener existed only to seed defaults, and without an onError a
        // config outage escaped to the zone as an uncaught exception.
      },
    );
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
    _signInEmail.text = q['email'] ?? '';
    _recalcAmount();
    _months.addListener(_recalcAmount);
    // A previous visit's session persists across page loads (Supabase Web
    // SDK default) — pick it back up without asking to sign in again.
    _authAccountId = Supabase.instance.client.auth.currentUser?.id;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        final id = state.session?.user.id;
        if (id == _authAccountId) return;
        _authAccountId = id;
        _clearAccountData();
        if (id != null) unawaited(_loadAccountData());
      },
      onError: (_) {
        if (mounted) {
          setState(
            () => _signInError = AppLocalizations.of(
              context,
            ).storefrontRenewSignInFailed,
          );
        }
      },
    );
    if (_authAccountId != null) unawaited(_loadAccountData());
  }

  /// The price per month/year is admin-fixed, not negotiable — so unlike a
  /// storefront cart, this is the exact amount owed, not a suggestion the
  /// owner can override (see [_amountLocked]). Yearly rounds the month
  /// count up to the nearest whole year so a mid-year top-up (e.g. 18
  /// months) still charges a sane amount rather than under-charging.
  void _recalcAmount() {
    _amount.text = '${_plan == 'yearly' ? _priceYearlyMmk : _priceMonthlyMmk}';
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _signInEmail.text.trim(),
        password: _signInPassword.text,
      );
      if (!mounted) return;
      _signInPassword.clear();
    } catch (e) {
      if (mounted) setState(() => _signInError = l.storefrontRenewSignInFailed);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      if (!await _auth.signInWithGoogle()) {
        throw StateError('oauth_not_opened');
      }
    } catch (_) {
      if (mounted) setState(() => _signInError = l.storefrontRenewSignInFailed);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _clearAccountData() {
    _accountGeneration++;
    _preparedAccountId = null;
    if (!mounted) return;
    setState(() {
      _myRequests = null;
      _shops = null;
      _shopId = null;
      _cardPayment = false;
      _mmqrPayment = false;
      _region = null;
      _clientRequestId = null;
      _proofBytes = null;
      _proofName = null;
      _proofExt = null;
      _refNo.clear();
      _signInError = null;
      _loadingHistory = false;
    });
  }

  Future<void> _signOut() async {
    // Clear private shop/history data even if the network sign-out fails.
    _clearAccountData();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        setState(
          () => _signInError = AppLocalizations.of(
            context,
          ).storefrontRenewSignInFailed,
        );
      }
    }
  }

  /// Runs right after sign-in (and once on page load if a session already
  /// persisted from a previous visit): prefills the shop name from the
  /// account's own profile and loads its request history. Best-effort on
  /// the name — a fetch failure there shouldn't block seeing history, which
  /// is the actual point of signing in.
  Future<void> _loadAccountData() async {
    final accountId = Supabase.instance.client.auth.currentUser?.id;
    if (!mounted || accountId == null) return;
    final generation = ++_accountGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _accountGeneration &&
        Supabase.instance.client.auth.currentUser?.id == accountId;
    setState(() {
      _loadingHistory = true;
      _signInError = null;
    });
    try {
      if (_preparedAccountId != accountId) {
        final owner = await _auth.prepareAccount();
        if (!isCurrent()) return;
        if (!owner) {
          setState(() {
            _shops = [];
            _shopId = null;
            _myRequests = [];
          });
          return;
        }
        _preparedAccountId = accountId;
      }
      final billing = await _api.fetchBillingShops();
      final shops = billing.shops;
      if (!isCurrent()) return;
      setState(() {
        _shops = shops;
        _cardPayment = billing.cardPayment;
        _mmqrPayment = billing.mmqrPayment;
        if (!shops.any((s) => s['shop_id'] == _shopId)) {
          _shopId = shops.isEmpty ? null : shops.first['shop_id'] as String;
        }
      });
      // Only now is the shop known, and a cached order belongs to one shop.
      if (_mmqrOrder == null) _restoreMmqrOrder();
      final selected = _shopId;
      final rows = selected == null
          ? <RenewalRequestSummary>[]
          : await _api.fetchMyRequests(selected);
      if (isCurrent() && _shopId == selected) {
        setState(() => _myRequests = rows);
      }
      // After the list, not with it: this one reaches the processor, and a
      // slow answer must not hold up the page the owner came to use.
      final card = selected == null
          ? null
          : await _api.cardSubscription(shopId: selected);
      if (isCurrent() && _shopId == selected) {
        setState(() => _cardSubscription = card);
      }
    } catch (_) {
      if (isCurrent()) {
        setState(
          () =>
              _signInError = AppLocalizations.of(context).storefrontRenewFailed,
        );
      }
    } finally {
      if (isCurrent()) setState(() => _loadingHistory = false);
    }
  }

  // ---------------------------------------------------------------------
  // MMQR. Local rail, MMK, settled by MyanMyanPay.
  // ---------------------------------------------------------------------

  /// Reads back an order cached by a previous load of this page.
  ///
  /// Required by MMPay: coming back from the banking app must not lose the
  /// order, and a refresh must restore the same order and QR rather than
  /// issuing a new one. The cache is only a hint about *which* order to ask
  /// about — the server's `mmqr_status` decides what state it is in.
  void _restoreMmqrOrder() {
    final cached = loadMmqrOrder();
    if (cached == null) return;
    if (cached.shopId != _shopId) return;
    setState(() {
      _plan = cached.plan == 'yearly' ? 'yearly' : 'monthly';
      _mmqrOrder = cached.order;
      _mmqrStatus = MmqrStatus.pending;
    });
    _startMmqrPolling();
    unawaited(_refreshMmqrStatus());
  }

  /// Issues an MMQR for the selected shop. The server owns the amount and the
  /// term; this sends only the shop and the plan.
  Future<void> _payByMmqr() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final shopId = _shopId;
    if (shopId == null || _mmqrBusy) return;
    setState(() => _mmqrBusy = true);
    try {
      final order = await _api.createMmqr(shopId: shopId, plan: _plan);
      if (!mounted) return;
      if (order == null) {
        // Already paid, and the server settled it on the spot — the
        // webhook-never-arrived case healing itself.
        clearMmqrOrder();
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewMmqrPaid)),
        );
        return;
      }
      saveMmqrOrder(shopId, _plan, order);
      setState(() {
        _mmqrOrder = order;
        _mmqrStatus = MmqrStatus.pending;
      });
      _startMmqrPolling();
    } on CheckoutAlreadySubscribed {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewCardExists)),
        );
      }
    } on CheckoutInProgress {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewCardPending)),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewMmqrUnavailable)),
        );
      }
    } finally {
      if (mounted) setState(() => _mmqrBusy = false);
    }
  }

  /// Four seconds, well inside MMPay's 1000/minute limit. This is what makes
  /// the renewal land when the callback is late rather than only when it is
  /// on time.
  void _startMmqrPolling() {
    _mmqrPoll?.cancel();
    _mmqrPoll = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshMmqrStatus()),
    );
  }

  Future<void> _refreshMmqrStatus() async {
    final shopId = _shopId;
    final order = _mmqrOrder;
    if (shopId == null || order == null) return;
    final MmqrStatus status;
    try {
      status = await _api.mmqrStatus(shopId: shopId, orderId: order.orderId);
    } catch (_) {
      // A failed poll is not an outcome. Keep the code on screen and ask
      // again — the owner may be mid-payment on their phone.
      return;
    }
    if (!mounted || _mmqrOrder?.orderId != order.orderId) return;
    setState(() => _mmqrStatus = status);
    if (status.isPaid || status.isDead) {
      _mmqrPoll?.cancel();
      clearMmqrOrder();
      if (status.isPaid) unawaited(_loadAccountData());
    }
  }

  /// MMPay forbids a second order while one is live unless the owner
  /// explicitly cancels, so this really cancels at MMPay — and re-queries
  /// first, because cancelling an order that was in fact paid must grant the
  /// term rather than throw it away.
  Future<void> _cancelMmqr() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final shopId = _shopId;
    final order = _mmqrOrder;
    if (shopId == null || order == null || _mmqrBusy) return;
    setState(() => _mmqrBusy = true);
    try {
      final paid = await _api.cancelMmqr(
        shopId: shopId,
        orderId: order.orderId,
      );
      if (!mounted) return;
      _mmqrPoll?.cancel();
      clearMmqrOrder();
      setState(
        () => _mmqrStatus = paid ? MmqrStatus.success : MmqrStatus.cancelled,
      );
      if (paid) unawaited(_loadAccountData());
    } catch (_) {
      // Unknown outcome: leave the order on screen and let the poll settle it
      // rather than telling the owner it is gone when it may not be.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewMmqrUnavailable)),
        );
      }
    } finally {
      if (mounted) setState(() => _mmqrBusy = false);
    }
  }

  void _startMmqrAgain() {
    _mmqrPoll?.cancel();
    clearMmqrOrder();
    setState(() {
      _mmqrOrder = null;
      _mmqrStatus = MmqrStatus.pending;
    });
  }

  /// International card purchase: the server creates the checkout (it picks
  /// the amount, the term and the mode) and this opens the processor's own
  /// hosted page. Premium is not granted here — the signed webhook does that,
  /// and the app picks it up on its next receipt refresh.
  Future<void> _payByCard() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final shopId = _shopId;
    if (shopId == null || _openingCheckout) return;
    setState(() => _openingCheckout = true);
    try {
      final url = await _api.createCheckout(shopId: shopId, plan: _plan);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      )) {
        throw Exception('launch_failed');
      }
    } on CheckoutAlreadySubscribed catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.storefrontRenewCardExists),
            duration: const Duration(seconds: 10),
            action: error.managementUrl == null
                ? null
                : SnackBarAction(
                    label: l.storefrontRenewCardManage,
                    onPressed: () => _openCardManagement(error.managementUrl!),
                  ),
          ),
        );
      }
    } on CheckoutInProgress {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewCardPending)),
        );
      }
    } on CheckoutUnavailable {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewCardUnavailable)),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.storefrontRenewFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _openingCheckout = false);
    }
  }

  Future<void> _openCardManagement(Uri url) async {
    try {
      if (!await launchUrl(url,
          mode: LaunchMode.platformDefault, webOnlyWindowName: '_self')) {
        throw const FormatException('launch_failed');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).storefrontRenewFailed),
          ),
        );
      }
    }
  }

  void _openHistoryReceipt(RenewalRequestSummary r) {
    setState(() {
      _submitted = true;
      _requestId = r.id;
      _invoiceNo = r.invoiceNo;
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _mmqrPoll?.cancel();
    _accountGeneration++;
    _phone.dispose();
    _amount.dispose();
    _refNo.dispose();
    _months.dispose();
    _signInEmail.dispose();
    _signInPassword.dispose();
    _hp.dispose();
    super.dispose();
  }

  void _onPlanChanged(String plan) {
    setState(() {
      _plan = plan;
      _months.text = plan == 'yearly' ? '12' : '1';
    });
  }

  /// See storefront_page.dart's _pickProof — same HEIC/size trap, and
  /// worse here: the owner has already transferred the money.
  Future<void> _pickProof() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    final c = await compressImage(
      Uint8List.fromList(file.bytes!),
      fallbackExt: (file.extension ?? 'jpg').toLowerCase(),
    );
    const uploadable = {'jpg', 'jpeg', 'png', 'webp'};
    const maxProofBytes = 5 * 1024 * 1024;
    if (!uploadable.contains(c.ext) || c.bytes.length > maxProofBytes) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadable.contains(c.ext)
                ? l.storefrontProofTooLarge
                : l.storefrontProofUnsupported,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _proofBytes = c.bytes;
      _proofExt = c.ext;
      _proofName = file.name;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final shopId = _shopId;
    final months = int.tryParse(_months.text.trim()) ?? 0;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final refNo = _refNo.text.trim();
    if (shopId == null ||
        Supabase.instance.client.auth.currentSession == null ||
        months <= 0 ||
        amount <= 0 ||
        refNo.length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.storefrontRenewMissingFields)));
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
          folder: '_admin/${Supabase.instance.client.auth.currentUser!.id}',
        );
      }
      final submitted = await _api.submitLicenseRequest(
        clientRequestId: _clientRequestId ??= const Uuid().v4(),
        shopId: shopId,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
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
        locale: widget.locale,
        onToggle: widget.onToggleLocale,
      ),
      body: _submitted ? _afterSubmit(l) : _form(l),
    );
  }

  Widget _afterSubmit(AppLocalizations l) {
    final id = _requestId;
    // The receipt IS the confirmation — it says the same "we got it" and
    // then keeps saying something useful every time the shop comes back.
    if (id != null) {
      // `_submitted` is set by submitting AND by tapping a past receipt in
      // the history list, and nothing ever cleared it — so an owner who
      // opened last month's receipt could not get back to the form to file
      // THIS month's renewal without reloading the page. The receipt view
      // itself offers only Refresh / Copy / Print.
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _submitted = false;
                _requestId = null;
                _invoiceNo = null;
                // A new submission is a new request — never reuse the id,
                // or the server would replay the old one.
                _clientRequestId = null;
              }),
              icon: const Icon(Icons.arrow_back),
              label: Text(l.onboardBack),
            ),
          ),
          Expanded(
            child: RenewalReceiptView(
              requestId: id,
              initialInvoiceNo: _invoiceNo,
              supportViber: _supportViber,
            ),
          ),
        ],
      );
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
            Icon(
              Icons.check_circle,
              color: AppColors.of(context).success,
              size: 48,
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              l.storefrontRenewSubmitted,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Sign-in convenience card, shown above the form itself. Signed out: a
  /// compact email/password sign-in. Signed in: who's signed in + Sign out
  /// + the request history (shop name/email above were already prefilled by
  /// [_loadAccountData]).
  Widget _accountSection(AppLocalizations l) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: email == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.storefrontRenewSignInPrompt,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (Env.googleAuthEnabled) ...[
                    const SizedBox(height: AppTheme.space3),
                    OutlinedButton.icon(
                      onPressed: _signingIn ? null : _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: Text(l.accountContinueGoogle),
                    ),
                  ],
                  const SizedBox(height: AppTheme.space2),
                  TextField(
                    controller: _signInEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: l.accountEmail),
                  ),
                  const SizedBox(height: AppTheme.space2),
                  TextField(
                    controller: _signInPassword,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l.accountPassword),
                    onSubmitted: (_) => _signingIn ? null : _signIn(),
                  ),
                  if (_signInError != null) ...[
                    const SizedBox(height: AppTheme.space1),
                    Text(
                      _signInError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.of(context).danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.space2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _signingIn ? null : _signIn,
                      icon: _signingIn
                          ? const ButtonSpinner(size: 16)
                          : const Icon(Icons.login),
                      label: Text(l.accountSignIn),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.storefrontRenewSignedInAs(email),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _signOut,
                        child: Text(l.accountSignOut),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space2),
                  _historyList(l),
                ],
              ),
      ),
    );
  }

  Widget _historyList(AppLocalizations l) {
    if (_loadingHistory) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.space2),
        child: Center(child: ButtonSpinner()),
      );
    }
    final requests = _myRequests ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.storefrontRenewHistoryTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppTheme.space1),
        if (requests.isEmpty)
          Text(
            l.storefrontRenewHistoryEmpty,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final r in requests) _historyRow(l, r),
      ],
    );
  }

  Widget _historyRow(AppLocalizations l, RenewalRequestSummary r) {
    final (Color tone, String statusLabel) = switch (r.status) {
      'fulfilled' => (AppColors.of(context).success, l.receiptStatusFulfilled),
      'rejected' => (AppColors.of(context).danger, l.receiptStatusRejected),
      _ => (AppColors.of(context).warning, l.receiptStatusPending),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(r.invoiceNo.isNotEmpty ? r.invoiceNo : r.id),
      subtitle: Text('${_ks(l, r.amount)} · $statusLabel'),
      trailing: Icon(Icons.chevron_right, color: tone),
      onTap: () => _openHistoryReceipt(r),
    );
  }

  Widget _form(AppLocalizations l) {
    if (Supabase.instance.client.auth.currentSession == null ||
        _shopId == null) {
      return ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(
            l.storefrontRenewTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppTheme.space3),
          _accountSection(l),
          if (_shops?.isEmpty == true) Text(l.billingNoShops),
          if (_signInError != null) Text(_signInError!),
          if (Supabase.instance.client.auth.currentSession != null)
            TextButton(onPressed: _loadAccountData, child: Text(l.commonRetry)),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.storefrontRenewTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l.storefrontRenewIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTheme.space4),
          _accountSection(l),
          const SizedBox(height: AppTheme.space4),
          // Honeypot — kept out of the visible layout entirely (zero size),
          // so no real user can tab/scroll into it.
          Offstage(child: TextField(controller: _hp, autofocus: false)),
          DropdownButtonFormField<String>(
            initialValue: _shopId,
            decoration: InputDecoration(labelText: l.billingSelectShop),
            items: [
              for (final shop in _shops ?? <Map<String, dynamic>>[])
                DropdownMenuItem(
                  value: shop['shop_id'] as String,
                  child: Text('${shop['name']}'),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    // A live order belongs to the shop it was issued for;
                    // it must never be shown against another one.
                    _mmqrPoll?.cancel();
                    setState(() {
                      _shopId = value;
                      _clientRequestId = null;
                      _myRequests = null;
                      _mmqrOrder = null;
                      _mmqrStatus = MmqrStatus.pending;
                      _cardSubscription = null;
                    });
                    _loadAccountData();
                  },
          ),
          if (_cardSubscription != null) ...[
            const SizedBox(height: AppTheme.space4),
            _CardSubscriptionPanel(
              subscription: _cardSubscription!,
              onManage: _openCardManagement,
            ),
          ],
          const SizedBox(height: AppTheme.space4),
          SectionHeader(title: l.storefrontRenewRegion),
          const SizedBox(height: AppTheme.space2),
          Row(
            children: [
              Expanded(
                child: _RegionCard(
                  flag: '🇲🇲',
                  label: 'Myanmar',
                  selected: _region == 'mm',
                  onTap: _submitting
                      ? null
                      : () => setState(() => _region = 'mm'),
                ),
              ),
              const SizedBox(width: AppTheme.space3),
              Expanded(
                child: _RegionCard(
                  flag: '🌏',
                  label: l.storefrontRenewRegionOther,
                  selected: _region == 'intl',
                  onTap: _submitting
                      ? null
                      : () => setState(() => _region = 'intl'),
                ),
              ),
            ],
          ),
          if (_region == null) ...[
            const SizedBox(height: AppTheme.space4),
            Text(
              l.storefrontRenewRegionHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_region != null) ...[
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
              ButtonSegment(
                value: 'monthly',
                label: Text(l.licensePlanMonthly),
              ),
              ButtonSegment(value: 'yearly', label: Text(l.licensePlanYearly)),
            ],
            selected: {_plan},
            onSelectionChanged: (s) => _onPlanChanged(s.first),
          ),
          Builder(
            builder: (context) {
              final String priceLabel;
              if (_region == 'intl') {
                final sgd = _plan == 'yearly' ? _priceYearlyIntl : _priceMonthlyIntl;
                final formatted = 'SGD ${(sgd / 100).toStringAsFixed(2)}';
                priceLabel = _plan == 'yearly'
                    ? l.storefrontRenewPricePerYear(formatted)
                    : l.storefrontRenewPricePerMonth(formatted);
              } else {
                final price = _plan == 'yearly' ? _priceYearlyMmk : _priceMonthlyMmk;
                priceLabel = _plan == 'yearly'
                    ? l.storefrontRenewPricePerYear(_ks(l, price))
                    : l.storefrontRenewPricePerMonth(_ks(l, price));
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppTheme.space1),
                child: Text(priceLabel, style: Theme.of(context).textTheme.bodySmall),
              );
            },
          ),
          // Months is only relevant for the Myanmar manual-transfer path;
          // Lemon Squeezy handles its own billing cycle.
          if (_region == 'mm') ...[
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _months,
              readOnly: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: InputDecoration(labelText: l.storefrontRenewMonths),
            ),
          ],
          // --- Myanmar: MMQR + manual local transfer ---
          if (_region == 'mm') ...[
            if (_mmqrOrder != null) ...[
              const SizedBox(height: AppTheme.space4),
              MmqrCheckout(
                order: _mmqrOrder!,
                status: _mmqrStatus,
                busy: _mmqrBusy,
                onCancel: _cancelMmqr,
                onStartAgain: _startMmqrAgain,
              ),
            ] else if (_mmqrPayment) ...[
              const SizedBox(height: AppTheme.space4),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.storefrontRenewMmqrTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        l.storefrontRenewMmqrBody,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppTheme.space3),
                      FilledButton.icon(
                        onPressed: _mmqrBusy || _submitting || _shopId == null
                            ? null
                            : _payByMmqr,
                        icon: _mmqrBusy
                            ? const ButtonSpinner()
                            : const Icon(Icons.qr_code_2),
                        label: Text(l.storefrontRenewMmqrCta),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.storefrontNumberCopied)),
                            );
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
              readOnly: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l.storefrontRenewAmountPaid,
                helperText: l.storefrontRenewAmountLockedHint,
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
              label: Text(
                _proofName == null
                    ? l.storefrontAttachProof
                    : l.storefrontProofAttached(_proofName!),
              ),
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
          // --- International: Lemon Squeezy card ---
          if (_region == 'intl') ...[
            if (_cardPayment) ...[
              const SizedBox(height: AppTheme.space4),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.storefrontRenewCardTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        l.storefrontRenewCardBody,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppTheme.space3),
                      FilledButton.icon(
                        onPressed: _openingCheckout || _submitting
                            ? null
                            : _payByCard,
                        icon: _openingCheckout
                            ? const ButtonSpinner()
                            : const Icon(Icons.credit_card),
                        label: Text(l.storefrontRenewCardCta),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: AppTheme.space4),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    children: [
                      Icon(
                        Icons.credit_card_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppTheme.space2),
                      Text(
                        l.storefrontRenewCardUnavailable,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          // Close the `if (_region != null)` block opened above.
          ],
          if (_region != null && (_supportViber ?? '').isNotEmpty) ...[
            const SizedBox(height: AppTheme.space3),
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    openSupportViber(context, number: _supportViber!),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(l.storefrontRenewUrgentViber),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tappable region selection card with flag emoji and label.
class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String flag;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      color: selected ? scheme.primaryContainer : scheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.space4,
            horizontal: AppTheme.space3,
          ),
          child: Column(
            children: [
              Text(flag, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: AppTheme.space2),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shop's card subscription, and the way out of it.
///
/// Shown whenever one exists, not only when a second purchase is refused.
/// A recurring charge whose only visible exit is to try buying again and read
/// a snackbar is the kind of thing people reasonably resent, and several app
/// stores require a plain route to cancelling.
class _CardSubscriptionPanel extends StatelessWidget {
  const _CardSubscriptionPanel({
    required this.subscription,
    required this.onManage,
  });

  final CardSubscription subscription;
  final void Function(Uri) onManage;

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cancelled = subscription.isCancelled;
    final ends = subscription.endsAt;
    final renews = subscription.renewsAt;
    final String body;
    if (subscription.status == 'past_due' || subscription.status == 'unpaid') {
      body = l.storefrontRenewCardPastDue;
    } else if (cancelled && ends != null) {
      body = l.storefrontRenewCardCancelled(_date(ends));
    } else if (!cancelled && renews != null) {
      body = l.storefrontRenewCardRenews(_date(renews));
    } else {
      // A status with no date to show still gets the way out, which is the
      // part that matters.
      body = l.storefrontRenewCardCancelHint;
    }
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.credit_card,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.space2),
                Text(
                  l.storefrontRenewCardActiveTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            Text(body, style: theme.textTheme.bodySmall),
            if (subscription.managementUrl != null) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                l.storefrontRenewCardCancelHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space3),
              OutlinedButton.icon(
                onPressed: () => onManage(subscription.managementUrl!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l.storefrontRenewCardManageOrCancel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
