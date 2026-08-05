import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/branch_repository.dart';

void main() {
  group('BranchSwitchRecoveryState', () {
    test('round-trips through json payload', () {
      final state = BranchSwitchRecoveryState(
        token: 'tok-1',
        fromShopId: 'shop-a',
        toShopId: 'shop-b',
        step: BranchSwitchStep.refreshingSession,
        startedAt: DateTime.utc(2026, 8, 5, 10, 0, 0),
        lastError: 'network_error',
        needsSyncRetry: true,
      );

      final decoded = BranchSwitchRecoveryState.fromJson(state.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.token, 'tok-1');
      expect(decoded.fromShopId, 'shop-a');
      expect(decoded.toShopId, 'shop-b');
      expect(decoded.step, BranchSwitchStep.refreshingSession);
      expect(decoded.lastError, 'network_error');
      expect(decoded.needsSyncRetry, isTrue);
    });

    test('returns null for incomplete payload', () {
      final decoded = BranchSwitchRecoveryState.fromJson({
        'token': 'tok-1',
        'from_shop_id': 'shop-a',
      });
      expect(decoded, isNull);
    });
  });
}
