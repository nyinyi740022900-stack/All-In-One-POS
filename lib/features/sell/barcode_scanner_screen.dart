import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'hardware_scanner_listener.dart';

/// Full-screen barcode capture. Uses the camera on phones/tablets, and a
/// USB / Bluetooth HID scanner on computers (and as a second path on
/// mobile). Pops with the first decoded value.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    if (isCameraBarcodeSupported) {
      _controller = MobileScannerController(
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
    if (_handled || code.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(code);
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
          ],
        ),
        body: camera == null
            ? _HardwareOnlyBody(message: l.scanHardwareOnlyHint)
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
                              l.scanHardwareHint,
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
