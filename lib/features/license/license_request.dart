import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Submits a self-service subscription request to the backend `license_requests`
/// table (RLS allows anonymous inserts). The admin reviews the payment and
/// issues a key. Fire-and-forget: the app never reads requests back.
class LicenseRequestService {
  static const _uuid = Uuid();

  static Future<void> submit({
    required String shopName,
    String? phone,
    required String plan,
    required int months,
    required String method,
    required int amount,
    String? refNo,
    required String deviceId,
    String? tier,
    String? paymentProofPath,
    String? shopId,
  }) async {
    await Supabase.instance.client.from('license_requests').insert({
      'id': _uuid.v4(),
      'shop_name': shopName,
      'phone': phone,
      'plan': plan,
      'months': months,
      'method': method,
      'amount': amount,
      'ref_no': refNo,
      'device_id': deviceId,
      'tier': ?tier,
      'payment_proof_path': ?paymentProofPath,
      'shop_id': ?shopId,
    });
  }
}
