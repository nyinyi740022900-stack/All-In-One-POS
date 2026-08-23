import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'hardware_scanner_listener.dart';
import 'scan_gate.dart';

/// Full-screen barcode capture. Uses the camera on phones/tablets, and a
/// USB / Bluetooth HID scanner on computers (and as a second path on
/// mobile).
///
/// Two modes:
/// - default (`const BarcodeScannerScreen()`): pops with the FIRST decoded
///   value — for one-shot lookups (product form, license, invoices).
/// - [BarcodeScannerScreen.continuous]: stays open and fires [onCode] for
///   EVERY scan so a cashier can add many items in one session; the Done
///   button (or back) closes it (owner request: scan-scan-scan → done,
///   instead of re-opening the camera per item).
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key})
      : continuous = false,
        onCode = null;

  const BarcodeScannerScreen.continuous({super.key, required this.onCode})
      : continuous = true;

  /// Whether scans keep the screen open ([true]) or pop with the first
  /// code ([false]).
  final bool continuous;

  /// Continuous-mode sink for each decoded barcode.
  final ValueChanged<String>? onCode;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;

  /// One physical scan = one addition. Camera decoders re-fire while a
  /// barcode sits in frame; this swallows the duplicates (POS-standard
  /// per-code cooldown) without blocking deliberate later re-scans.
  final _gate = ScanGate();

  @override
  void initState() {
    super.initState();
    if (isCameraBarcodeSupported) {
      _controller = MobileScannerController(
        // noDuplicates only suppresses identical CONSECUTIVE captures, so
        // deliberately re-scanning an item still adds it again.
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (code.isEmpty) return;
    if (widget.continuous) {
      if (!_gate.accept(code, DateTime.now())) return;
      widget.onCode?.call(code);
    } else {
      Navigator.of(context).pop(code);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (code == null || code.isEmpty) return;
    _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final camera = _controller;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final frameWidth = (shortestSide * 0.72).clamp(200.0, 360.0);

    return HardwareScannerListener(
      onScan: _finish,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.scanBarcode),
          actions: [
            if (camera != null) ...[
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: camera,
                builder: (context, state, _) {
                  final on = state.torchState == TorchState.on;
                  return IconButton(
                    isSelected: on,
                    icon: const Icon(Icons.flash_off),
                    selectedIcon: const Icon(Icons.flash_on),
                    tooltip: l.scanTorch,
                    onPressed: state.torchState == TorchState.unavailable
                        ? null
                        : () => camera.toggleTorch(),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.cameraswitch),
                tooltip: l.scanFlip,
                onPressed: () => camera.switchCamera(),
              ),
            ],
            if (widget.continuous)
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: Text(l.scanDone),
              ),
          ],
        ),
        body: camera == null
            ? _HardwareOnlyBody(
                message:
                    widget.continuous ? l.scanContinuousHint : l.scanHardwareOnlyHint)
            : Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(controller: camera, onDetect: _onDetect),
                  Container(
                    width: frameWidth,
                    height: frameWidth * 0.64,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.space5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.space4,
                              vertical: AppTheme.space2,
                            ),
                            child: Text(
                              widget.continuous
                                  ? l.scanContinuousHint
                                  : l.scanHardwareHint,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _HardwareOnlyBody extends StatelessWidget {
  const _HardwareOnlyBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
