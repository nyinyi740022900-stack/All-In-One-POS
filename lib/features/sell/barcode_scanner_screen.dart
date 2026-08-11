import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Full-screen camera barcode scanner. Pops with the first decoded value.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (code == null || code.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // The "surface" behind everything here is a live camera image, not a
    // theme surface — it is neither light nor dark and doesn't recolor — so
    // white-on-scrim is the deliberate choice for the overlay, not a missed
    // token. Everything that *is* theme-driven (shape, spacing, type) still
    // comes from `AppTheme`.
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final frameWidth = (shortestSide * 0.72).clamp(200.0, 360.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.scanBarcode),
        actions: [
          // Reflects the real torch state instead of a fixed "flash on"
          // glyph: tapping the old button changed nothing on screen, so in a
          // dark stockroom there was no way to tell whether the light was
          // meant to be on and the phone had refused, or you had simply
          // missed the button.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                isSelected: on,
                icon: const Icon(Icons.flash_off),
                selectedIcon: const Icon(Icons.flash_on),
                tooltip: l.scanTorch,
                onPressed: state.torchState == TorchState.unavailable
                    ? null
                    : () => _controller.toggleTorch(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: l.scanFlip,
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Viewfinder guide, sized off the device rather than a fixed
          // 250x160 box — on a small phone that was most of the width, on a
          // tablet a stamp in the middle of the frame.
          Container(
            width: frameWidth,
            height: frameWidth * 0.64,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
          ),
          // Bottom-aligned inside the safe area: the old fixed 48pt offset
          // sat under the home indicator on a gesture-nav phone.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space4,
                        vertical: AppTheme.space2),
                    child: Text(
                      l.scanHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
