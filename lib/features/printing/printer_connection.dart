import 'package:flutter/foundation.dart';

/// How this device talks to the thermal receipt printer.
///
/// Stored per device (not synced). A phone and a shop PC each remember their
/// own connection — they can still target the *same* Wi-Fi printer by entering
/// the same IP on both.
enum PrinterConnection { bluetooth, network, usb }

class PrintResult {
  final bool ok;
  final String? error;
  const PrintResult(this.ok, [this.error]);
}

/// Host + port for an ESC/POS printer on the LAN. Cheap Wi-Fi thermal
/// printers (Xprinter, Rongta, Epson TM, …) listen on TCP **9100** by default
/// (JetDirect/RAW) — the same bytes we already send over Bluetooth.
class NetworkPrinterAddress {
  final String host;
  final int port;
  const NetworkPrinterAddress(this.host, {this.port = defaultPort});

  static const int defaultPort = 9100;

  /// Canonical form stored in `printer.mac` for a network printer — host
  /// alone when using the default port, otherwise `host:port`.
  String get encoded => port == defaultPort ? host : '$host:$port';

  /// Accepts `192.168.1.100`, `192.168.1.100:9100`, or a hostname. IPv6 is
  /// out of scope — these printers are IPv4 on a shop LAN.
  static NetworkPrinterAddress? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) return null;

    String host = trimmed;
    var port = defaultPort;
    final colon = trimmed.lastIndexOf(':');
    if (colon > 0) {
      final portPart = trimmed.substring(colon + 1);
      final parsed = int.tryParse(portPart);
      if (parsed != null) {
        host = trimmed.substring(0, colon).trim();
        port = parsed;
      }
    }
    if (host.isEmpty || port < 1 || port > 65535) return null;
    return NetworkPrinterAddress(host, port: port);
  }
}

PrinterConnection printerConnectionFromStorage(String? raw) {
  for (final value in PrinterConnection.values) {
    if (value.name == raw) return value;
  }
  return PrinterConnection.bluetooth;
}

/// Connections this OS can actually drive. Phone/tablet: Bluetooth + Wi-Fi.
/// Windows shop PC: Wi-Fi + USB cable. Bluetooth on Windows is the existing
/// known gap (`print_bluetooth_thermal` is mobile-only).
List<PrinterConnection> printerConnectionsForPlatform() {
  if (kIsWeb) return const [];
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return const [PrinterConnection.bluetooth, PrinterConnection.network];
    case TargetPlatform.windows:
      return const [PrinterConnection.network, PrinterConnection.usb];
    default:
      return const [PrinterConnection.network];
  }
}

PrinterConnection defaultPrinterConnectionForPlatform() {
  final available = printerConnectionsForPlatform();
  if (available.contains(PrinterConnection.bluetooth)) {
    return PrinterConnection.bluetooth;
  }
  return available.isEmpty ? PrinterConnection.network : available.first;
}

bool printerConnectionSupported(PrinterConnection connection) =>
    printerConnectionsForPlatform().contains(connection);
