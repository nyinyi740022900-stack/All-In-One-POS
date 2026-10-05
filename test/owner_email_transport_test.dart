import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mm_pos/features/account/owner_email_transport.dart';

User user(String id) => User(
  id: id,
  appMetadata: {'role': 'owner', 'shop_id': 'shop-$id'},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '',
  email: '$id@example.com',
);
Future<void> login(SupabaseClient c, String id) => c.auth.setInitialSession(
  jsonEncode(
    Session(
      accessToken: 'token-$id',
      tokenType: 'bearer',
      user: user(id),
    ).toJson(),
  ),
);
void main() {
  test(
    'email request uses current bearer and preserves owner id and shop',
    () async {
      final c = SupabaseClient(
        'https://owner.test',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await login(c, 'a');
      final transport = MockClient((r) async {
        expect(r.method, 'PUT');
        expect(r.headers['authorization'], 'Bearer token-a');
        expect(jsonDecode(r.body), {'email': 'new@example.com'});
        expect(
          r.url.queryParameters['redirect_to'],
          'allinonepos://login-callback',
        );
        return http.Response(
          jsonEncode({...user('a').toJson(), 'new_email': 'new@example.com'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final updated = await requestOwnerEmail(
        c,
        'new@example.com',
        transport: transport,
      );
      expect(updated.id, 'a');
      expect(c.auth.currentUser!.appMetadata['shop_id'], 'shop-a');
      expect(c.auth.currentUser!.email, 'a@example.com');
      expect(c.auth.currentUser!.newEmail, 'new@example.com');
      await c.dispose();
    },
  );
  test(
    'late email response cannot overwrite a different signed-in owner',
    () async {
      final c = SupabaseClient(
        'https://owner.test',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await login(c, 'a');
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final task = requestOwnerEmail(
        c,
        'new@example.com',
        transport: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      final expectation = expectLater(task, throwsA(isA<StateError>()));
      await started.future;
      await login(c, 'b');
      pending.complete(
        http.Response(
          jsonEncode(user('a').toJson()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectation;
      expect(c.auth.currentUser!.id, 'b');
      expect(c.auth.currentUser!.appMetadata['shop_id'], 'shop-b');
      await c.dispose();
    },
  );
}
