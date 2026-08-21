import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hardware_scan_buffer.dart';

export 'hardware_scan_buffer.dart';

/// Camera barcode ([mobile_scanner]) is phone/tablet only. Windows uses a
/// USB or Bluetooth HID scanner instead.
bool get isCameraBarcodeSupported {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

/// Listens for a USB or Bluetooth barcode gun that emulates a keyboard.
/// Active only while this route is on top *and* this tab is the visible
/// shell branch (`TickerMode` is off for hidden IndexedStack children).
class HardwareScannerListener extends StatefulWidget {
  const HardwareScannerListener({
    super.key,
    required this.onScan,
    required this.child,
    this.enabled = true,
  });

  final ValueChanged<String> onScan;
  final Widget child;
  final bool enabled;

  @override
  State<HardwareScannerListener> createState() =>
      _HardwareScannerListenerState();
}

class _HardwareScannerListenerState extends State<HardwareScannerListener> {
  final _buffer = HardwareScanBuffer();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _listening {
    if (!mounted) return false;
    if (!widget.enabled) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  bool _hasBlockingModifier() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_listening) return false;
    if (_hasBlockingModifier()) {
      _buffer.reset();
      return false;
    }

    final key = event.logicalKey;
    final terminator =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab;
    final wasLikely = _buffer.isLikelyScan;
    final code = _buffer.add(
      now: DateTime.now(),
      isTerminator: terminator,
      character: terminator ? null : event.character,
    );
    if (code != null) {
      widget.onScan(code);
      return true;
    }
    // Swallow the rest of a burst so a focused TextField does not also
    // receive the gun's digits. The first character may still leak; Sell
    // clears search when it matches the completed code.
    if (terminator) return wasLikely;
    return _buffer.isLikelyScan;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
