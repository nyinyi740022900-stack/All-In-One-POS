import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/database_session.dart';

class _Session extends ChangeNotifier implements DatabaseSession {
  _Session(this.shopDb, this.shopId);
  @override
  final AppDatabase shopDb;
  @override
  AppDatabase get deviceDb => shopDb;
  @override
  String? shopId;
  @override
  Future<void> reopenForShop(String toShopId) async {
    shopId = toShopId;
    notifyListeners();
  }
  @override
  Future<void> reopenForShopPromotedFrom({required String fromShopId, required String toShopId}) => reopenForShop(toShopId);
  @override
  Future<void> disposeSessions() async {}
}

void main() {
  for (final shop in ['shop-one', 'shop-two']) {
    test('cold start scopes local work to the already-open $shop before license verification', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final session = _Session(db, shop);
      final container = ProviderContainer(overrides: [
        databaseSessionProvider.overrideWith((ref) => session),
      ]);
      addTearDown(container.dispose);
      addTearDown(db.close);
      expect(container.read(shopIdProvider), shop);
      // Explicit branch binding owns subsequent changes: a DB notification
      // must not recreate the state provider and reset an in-progress switch.
      container.read(shopIdProvider.notifier).state = 'next-shop';
      await session.reopenForShop('next-shop');
      expect(container.read(shopIdProvider), 'next-shop');
    });
  }
}
