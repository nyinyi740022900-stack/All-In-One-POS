import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Is this the app we built, or a repackaged copy?
///
/// A cracked APK has to be re-signed with someone else's key, so the
/// signing certificate is the one fact a repackager cannot keep. Android
/// release builds compare it against the certificates we sign with; a
/// mismatch, or a release build flipped to debuggable, stops the app before
/// any shop data opens (`TamperedApp`, owner call 2026-10-17).
///
/// It only ever blocks on a POSITIVE finding. When the facts can't be read
/// (an OS quirk, an unusual ROM) the app runs: locking a real shop out of its
/// till on a guess would cost more than a cracked copy does. Client-side
/// checks raise the cost of cracking; they cannot make it impossible. Cloud
/// sync, storefront and staff administration are enforced by the server
/// regardless.
///
/// iOS (App Store / FairPlay) and Windows are not checked here.
class AppIntegrity {
  AppIntegrity._();

  /// SHA-256 of every certificate a genuine Android build is signed with.
  static const allowedSigners = <String>{
    // Upload key (CN=All In One POS, Yangon): local release builds, CI and
    // the GitHub "android-latest" APK.
    'A80738070C8D447FEB1F6B1CF1EC3CDA897F5914EC623F99506BE8D79F43AFE4',
    // Google Play app signing keys — what Play installs carry. Read from
    // Play Console → Protected with Play → App signing → "Copy all
    // certificate fingerprints" (SHA-256) on 2026-10-17: the key in use
    // (also the one in the Digital Asset Links snippet) plus the two
    // previous / quantum-ready keys Play lists, since a rotated key keeps
    // the older ones in the APK's signing lineage.
    '5AF5B5F26006DB3D0237126B3BD6FDB9FADC81240C9D33E90447FCFB0B5C9B05',
    'D7A1DAB58FDFE35A5391E8C7B968716B5F3833F4839EE53690314ED56651D99D',
    '9B1DF4925FC5FD46BD8A3A065F1EBD37601B0440E0E2E1989237AA25BA37F41C',
  };

  /// Enforcement can only be on when the Play signing keys are listed —
  /// otherwise every Play install would be judged "not ours".
  static bool get playKeyKnown => allowedSigners.length >= 2;

  /// `--dart-define=APP_INTEGRITY=false` turns the check off for one build
  /// (an emergency escape hatch, e.g. a new Play signing key).
  static const bool enabledByBuild = bool.fromEnvironment(
    'APP_INTEGRITY',
    defaultValue: true,
  );

  static const _channel = MethodChannel('com.allinonepos.app/integrity');

  /// Runs before the app opens any data. Never throws.
  static Future<IntegrityVerdict> check() async {
    if (!kReleaseMode || kIsWeb || !Platform.isAndroid) {
      return IntegrityVerdict.genuine;
    }
    if (!enabledByBuild || !playKeyKnown) return IntegrityVerdict.genuine;
    try {
      final facts = await _channel.invokeMapMethod<String, Object?>('facts');
      return evaluate(
        signers: (facts?['signers'] as List?)?.cast<String>(),
        debuggable: facts?['debuggable'] == true,
        allowed: allowedSigners,
      );
    } on MissingPluginException {
      // Our own MainActivity registers this channel; a release Android
      // build without it has had its native side replaced.
      return IntegrityVerdict.tampered;
    } catch (_) {
      return IntegrityVerdict.unknown;
    }
  }

  /// The decision on its own, so it is unit-tested without a device.
  @visibleForTesting
  static IntegrityVerdict evaluate({
    required List<String>? signers,
    required bool debuggable,
    required Set<String> allowed,
  }) {
    if (debuggable) return IntegrityVerdict.tampered;
    if (signers == null || signers.isEmpty) return IntegrityVerdict.unknown;
    final normalized = signers.map(_normalize);
    final allowedNorm = allowed.map(_normalize).toSet();
    return normalized.any(allowedNorm.contains)
        ? IntegrityVerdict.genuine
        : IntegrityVerdict.tampered;
  }

  static String _normalize(String hex) =>
      hex.replaceAll(':', '').replaceAll(' ', '').toUpperCase();
}

enum IntegrityVerdict {
  /// Signed by us (or not a platform this check covers).
  genuine,

  /// Re-signed by someone else, or a release build made debuggable.
  tampered,

  /// Facts unreadable — treated as genuine.
  unknown,
}
