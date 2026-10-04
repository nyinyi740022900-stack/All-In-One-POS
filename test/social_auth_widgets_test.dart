import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/account_repository.dart';
import 'package:mm_pos/features/account/account_action_error.dart';
import 'package:mm_pos/features/account/social_auth.dart';
import 'package:mm_pos/features/account/social_auth_widgets.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

Widget host(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('social failures have specific localized messages', () async {
    for (final locale in const [Locale('en'), Locale('my')]) {
      final l = await AppLocalizations.delegate.load(locale);
      expect(
        accountActionErrorMessage(l, 'social_auth_failed'),
        l.accountSocialAuthFailed,
      );
      expect(
        accountActionErrorMessage(l, 'social_auth_unavailable'),
        l.accountSocialAuthUnavailable,
      );
      expect(
        accountActionErrorMessage(l, 'social_reauth_failed'),
        l.accountSocialReauthFailed,
      );
    }
  });

  testWidgets(
    'absent configuration renders neither provider buttons nor separator',
    (tester) async {
      await tester.pumpWidget(
        host(
          SocialAuthButtons(
            providers: const {},
            busy: false,
            onSelected: (_) => fail('unavailable'),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Or use email'), findsNothing);
    },
  );

  testWidgets(
    'only configured providers can be chosen and busy disables every choice',
    (tester) async {
      SocialAuthProvider? selected;
      await tester.pumpWidget(
        host(
          SocialAuthButtons(
            providers: const {SocialAuthProvider.google},
            busy: false,
            onSelected: (p) => selected = p,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('social-google')));
      expect(selected, SocialAuthProvider.google);
      expect(find.byKey(const ValueKey('social-apple')), findsNothing);
      await tester.pumpWidget(
        host(
          SocialAuthButtons(
            providers: SocialAuthProvider.values.toSet(),
            busy: true,
            onSelected: (_) => fail('busy action'),
          ),
        ),
      );
      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
    },
  );

  testWidgets(
    'Myanmar provider choices wrap without overflow at twice text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          SocialAuthButtons(
            providers: SocialAuthProvider.values.toSet(),
            busy: false,
            linking: true,
            onSelected: (_) {},
          ),
          locale: const Locale('my'),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    },
  );

  testWidgets(
    'native provider cancellation is silent and does not open setup',
    (tester) async {
      AccountActionResult? result = const AccountActionResult.failure(
        'sentinel',
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await runSocialSignIn(
                  context,
                  signIn: () async =>
                      const AccountActionResult.failure('auth_cancelled'),
                  completeSignup: (_) async =>
                      throw StateError('unexpected signup'),
                  confirmSwitch: () async =>
                      throw StateError('unexpected switch'),
                  cancelSession: () async => throw StateError(
                    'native cancellation acquired no session',
                  ),
                );
              },
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('new social account requires a trimmed nonempty shop name', (
    tester,
  ) async {
    String? submitted;
    AccountActionResult? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await runSocialSignIn(
                context,
                signIn: () async => const AccountActionResult.needsShopName(),
                completeSignup: (name) async {
                  submitted = name;
                  return const AccountActionResult.success('user');
                },
                confirmSwitch: () async =>
                    throw StateError('unexpected switch'),
                cancelSession: () async {},
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create shop'));
    await tester.pump();
    expect(submitted, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  My Shop  ');
    await tester.tap(find.text('Create shop'));
    await tester.pumpAndSettle();
    expect(submitted, 'My Shop');
    expect(result?.ok, isTrue);
  });

  testWidgets(
    'declining a real-shop switch cancels acquired session without attachment',
    (tester) async {
      var abandoned = false;
      AccountActionResult? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await runSocialSignIn(
                  context,
                  signIn: () async =>
                      const AccountActionResult.needsWipeConfirmation(),
                  completeSignup: (_) async =>
                      throw StateError('unexpected signup'),
                  confirmSwitch: () async =>
                      throw StateError('unexpected switch'),
                  cancelSession: () async {
                    abandoned = true;
                  },
                );
              },
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(abandoned, isTrue);
      expect(result, isNull);
    },
  );
  testWidgets('dismissed shop setup abandons the temporary session', (
    tester,
  ) async {
    var abandoned = false;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await runSocialSignIn(
                context,
                signIn: () async => const AccountActionResult.needsShopName(),
                completeSignup: (_) async =>
                    throw StateError('unexpected signup'),
                confirmSwitch: () async =>
                    throw StateError('unexpected switch'),
                cancelSession: () async {
                  abandoned = true;
                },
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(abandoned, isTrue);
  });

  testWidgets('deletion verification offers only supported linked identities', (
    tester,
  ) async {
    SocialAuthProvider? selected;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await chooseSocialReauthentication(context, const {
                SocialAuthProvider.apple,
              });
            },
            child: const Text('Delete'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('social-google')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('social-apple')));
    await tester.pumpAndSettle();
    expect(selected, SocialAuthProvider.apple);
    expect(find.byType(TextField), findsNothing);
  });
  for (final pendingResult in const [
    AccountActionResult.needsShopName(),
    AccountActionResult.needsWipeConfirmation(),
    AccountActionResult.failure('not_authenticated'),
    AccountActionResult.success('attached-user'),
  ]) {
    testWidgets(
      'unmounted flow abandons only unfinished auth: ${pendingResult.ok}/${pendingResult.needsShopName}/${pendingResult.needsWipeConfirmation}',
      (tester) async {
        final response = Completer<AccountActionResult>();
        var abandoned = false;
        Future<AccountActionResult?>? flow;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  flow = runSocialSignIn(
                    context,
                    signIn: () => response.future,
                    completeSignup: (_) async =>
                        throw StateError('disposed signup'),
                    confirmSwitch: () async =>
                        throw StateError('disposed switch'),
                    cancelSession: () async {
                      abandoned = true;
                    },
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pumpWidget(host(const SizedBox()));
        response.complete(pendingResult);
        await tester.pumpAndSettle();
        expect(await flow, isNull);
        expect(abandoned, !pendingResult.ok);
      },
    );
  }

  for (final ownerRecovery in [false, true]) {
    testWidgets(
      'failed auth preserves a device-recovery session only for owner: $ownerRecovery',
      (tester) async {
        var abandoned = false;
        AccountActionResult? result;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await runSocialSignIn(
                    context,
                    signIn: () async => const AccountActionResult.failure(
                      'device_limit_reached',
                    ),
                    completeSignup: (_) async =>
                        throw StateError('unexpected signup'),
                    confirmSwitch: () async =>
                        throw StateError('unexpected switch'),
                    canRecoverDevice: () => ownerRecovery,
                    cancelSession: () async {
                      abandoned = true;
                    },
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        expect(result?.error, 'device_limit_reached');
        expect(abandoned, !ownerRecovery);
      },
    );
  }

  testWidgets(
    'failed verified social auth abandons session while retaining the error',
    (tester) async {
      var abandoned = false;
      AccountActionResult? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await runSocialSignIn(
                  context,
                  signIn: () async =>
                      const AccountActionResult.failure('not_authenticated'),
                  completeSignup: (_) async =>
                      throw StateError('unexpected signup'),
                  confirmSwitch: () async =>
                      throw StateError('unexpected switch'),
                  cancelSession: () async {
                    abandoned = true;
                  },
                );
              },
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(result?.error, 'not_authenticated');
      expect(abandoned, isTrue);
    },
  );
  for (final waitingForName in [true, false]) {
    testWidgets(
      'disposed entry abandons session after its prompt closes: name=$waitingForName',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        var abandoned = false;
        await tester.pumpWidget(
          host(
            ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) => show
                  ? Builder(
                      builder: (context) => TextButton(
                        onPressed: () async {
                          await runSocialSignIn(
                            context,
                            signIn: () async => waitingForName
                                ? const AccountActionResult.needsShopName()
                                : const AccountActionResult.needsWipeConfirmation(),
                            completeSignup: (_) async =>
                                throw StateError('disposed signup'),
                            confirmSwitch: () async =>
                                throw StateError('disposed switch'),
                            cancelSession: () async {
                              abandoned = true;
                            },
                          );
                        },
                        child: const Text('Start'),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        visible.value = false;
        await tester.pump();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(abandoned, isTrue);
      },
    );
  }
}
