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
    return Scaffold(
      appBar: AppBar(
        title: Text(l.scanBarcode),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: l.scanTorch,
            onPressed: () => _controller.toggleTorch(),
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
          // Simple viewfinder guide.
          Container(
            width: 250,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
          Positioned(
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space3, vertical: AppTheme.space2),
              color: Colors.black54,
              child: Text(l.scanHint,
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
