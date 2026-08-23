import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Scan feedback sounds (owner request: audible confirmation of whether a
/// scanned item was ACCEPTED or REJECTED). Two short tones ship as bundled
/// assets; playback failures (missing platform audio in tests/desktop
/// edge cases) are swallowed so scanning never breaks over sound.
class ScanSounds {
  ScanSounds._();
  static final ScanSounds instance = ScanSounds._();

  final AudioPlayer _ok = AudioPlayer();
  final AudioPlayer _err = AudioPlayer();

  bool _contextReady = false;

  /// iOS routes audio by an AVAudioSession category. respectSilence:false
  /// (the config default) maps to the playback category, so beeps are heard
  /// even with the ring/silent switch muted — a POS beep must always be
  /// audible (owner report: phone scans were silent).
  Future<void> _ensureContext() async {
    if (_contextReady) return;
    _contextReady = true;
    try {
      await AudioPlayer.global
          .setAudioContext(AudioContextConfig().build());
    } catch (_) {
      // Older platform implementations without global context — tones will
      // still play whenever the device is unmuted.
    }
  }

  /// Short high blip — item ADDED to the cart.
  Future<void> success() async {
    unawaited(_beep(_ok, 'sounds/scan_ok.wav'));
    HapticFeedback.selectionClick();
  }

  /// Low double-buzz — barcode NOT recognised / nothing added.
  Future<void> error() async {
    unawaited(_beep(_err, 'sounds/scan_err.wav'));
    HapticFeedback.heavyImpact();
  }

  Future<void> _beep(AudioPlayer player, String asset) async {
    try {
      await _ensureContext();
      // play() restarts from zero each call — no stop/resume bookkeeping,
      // and overlapping rapid scans simply restart the tone.
      await player.play(AssetSource(asset));
    } catch (_) {}
  }
}
