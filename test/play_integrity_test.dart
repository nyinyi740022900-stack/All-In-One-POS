import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/integrity/play_integrity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('request hash matches the server (_shared/play_integrity.ts)', () {
    // Same input as supabase/functions/tests/play_integrity_test.ts; if the
    // two ever differ, every Android token fails as "request_hash".
    expect(
      PlayIntegrity.requestHash('start_trial', 'dev-1', 'n-1'),
      'a5f3fe98bae2579439b48ef23593bff89f4ec12a40bfe51ce7e45973c98df3e9',
    );
  });

  test('gated actions mirror the server list', () {
    expect(PlayIntegrity.gatedActions, {
      'refresh_account_license',
      'resync_session',
      'switch_branch',
      'start_trial',
    });
  });

  test('platform names the server understands', () {
    expect(
      PlayIntegrity.platformFor(web: true, os: TargetPlatform.android),
      'web',
    );
    expect(
      PlayIntegrity.platformFor(web: false, os: TargetPlatform.android),
      'android',
    );
    expect(
      PlayIntegrity.platformFor(web: false, os: TargetPlatform.iOS),
      'ios',
    );
  });

  test('an Android call carries a token bound to its own nonce', () async {
    late String seenHash;
    final f = await PlayIntegrity.fields(
      'start_trial',
      'dev-1',
      tokenFor: (hash) async {
        seenHash = hash;
        return 'TOKEN';
      },
    );
    expect(f['platform'], 'android');
    expect(f['integrity_token'], 'TOKEN');
    final nonce = f['integrity_nonce'] as String;
    expect(nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(seenHash, PlayIntegrity.requestHash('start_trial', 'dev-1', nonce));
  });

  test('no token says why instead of failing the call', () async {
    final noServices = await PlayIntegrity.fields(
      'refresh_account_license',
      'd',
      tokenFor: (_) => Future.error(PlatformException(code: 'PI_-9')),
    );
    expect(noServices['integrity_token'], isNull);
    expect(noServices['integrity_error'], 'PI_-9');

    final slow = await PlayIntegrity.fields(
      'refresh_account_license',
      'd',
      tokenFor: (_) => Future.delayed(const Duration(seconds: 30), () => 'x'),
    );
    expect(slow['integrity_error'], 'timeout');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('calls outside the gated set are sent unchanged', () async {
    final body = {'action': 'list_staff'};
    expect(await PlayIntegrity.attach(body), same(body));
  });

  test('a build without the cloud project reports not_configured', () async {
    final body = await PlayIntegrity.attach({
      'action': 'start_trial',
      'device_id': 'd',
    });
    expect(body['integrity_error'], 'not_configured');
    expect(body['integrity_nonce'], isNotNull);
  });
}
