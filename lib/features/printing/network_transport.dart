import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'printer_connection.dart';

/// Sends already-built ESC/POS (or, with [prependInit] off, TSPL) bytes to
/// a Wi-Fi/LAN thermal printer.
Future<PrintResult> sendNetworkBytes(
  List<int> bytes,
  String address, {
  bool prependInit = true,
}) async {
  final parsed = NetworkPrinterAddress.tryParse(address);
  if (parsed == null) return const PrintResult(false, 'invalid_address');

  Socket? socket;
  try {
    socket = await Socket.connect(
      parsed.host,
      parsed.port,
      timeout: const Duration(seconds: 5),
    );
    final Uint8List payload;
    if (prependInit) {
      // ESC @ (initialize) first: wipes any half-received job an earlier
      // aborted print left in the printer's buffer. Epson-class printers
      // auto-REPRINT the buffered job after a comm error recovers, which is
      // exactly the "test print keeps printing forever" report. Only ESC/POS
      // understands it though — a TSPL label stream must start with its own
      // SIZE command, so label prints pass [prependInit] = false.
      payload = Uint8List(bytes.length + 2);
      payload[0] = 0x1b; // ESC
      payload[1] = 0x40; // @
      payload.setAll(2, bytes);
    } else {
      payload = Uint8List.fromList(bytes);
    }
    socket.add(payload);
    // Close gracefully (FIN) — NEVER destroy() on purpose: destroy() sends
    // RST mid-job, and printers that treat that as a comm error then
    // reprint the whole job (the "test print keeps printing forever"
    // report). Awaiting close() lets TCP confirm delivery of every byte
    // before we hang up.
    //
    // Both the write AND the close are bounded: flush() only completes once
    // the OS send buffer drains toward the printer, and a printer that
    // accepts the connection then stalls would otherwise pend here for
    // minutes (TCP retransmit timeout), wedging the serialized job queue
    // every transport shares. On timeout we tear down and report failure.
    try {
      await socket.flush().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              socket?.destroy();
              throw TimeoutException('printer write stalled');
            },
          );
      await socket.close().timeout(
            const Duration(seconds: 5),
            onTimeout: () => socket?.destroy(),
          );
    } on TimeoutException {
      return const PrintResult(false, 'network_timeout');
    }
    return const PrintResult(true);
  } on SocketException {
    return const PrintResult(false, 'network_unreachable');
  } catch (e) {
    return PrintResult(false, e.toString());
  } finally {
    socket?.destroy();
  }
}

/// Which /24 to walk, and which hosts are *this* device (never a printer).
///
/// Phones expose SEVERAL IPv4 interfaces at once — cellular (`pdp_ip0`,
/// `rmnet`), VPN (`utun`), Wi-Fi (`en0`/`wlan0`). Taking the first address
/// grabbed the CELLULAR /24 on iPhones with mobile data on, and the scan
/// found nothing on the Wi-Fi network the printer lives on. Prefer the
/// Wi-Fi/ethernet-shaped names; never scan through cellular or VPN; skip
/// every local address so the phone itself never lists as a printer.
({String? prefix, Set<String> skip}) lanScanPlan(
  Iterable<({String name, List<InternetAddress> addresses})> interfaces,
) {
  final skip = <String>{};
  String? preferred;
  String? fallback;
  for (final iface in interfaces) {
    final v4 = [
      for (final a in iface.addresses)
        if (a.type == InternetAddressType.IPv4 && !a.isLoopback) a,
    ];
    for (final a in v4) {
      skip.add(a.address);
    }
    if (v4.isEmpty) continue;
    final n = iface.name.toLowerCase();
    final cellular =
        n.startsWith('pdp') || n.startsWith('rmnet') ||
        n.startsWith('ccinet') || n.contains('wwan');
    final vpn =
        n.startsWith('utun') || n.startsWith('tap') || n.startsWith('tun');
    if (cellular || vpn) continue;
    final lanShaped =
        n.startsWith('en') || n.startsWith('wlan') || n.startsWith('eth');
    fallback ??= v4.first.address;
    if (lanShaped && preferred == null) preferred = v4.first.address;
  }
  final chosen = preferred ?? fallback;
  final prefix = chosen == null ? null : ipv4Prefix24(chosen);
  return (prefix: prefix, skip: skip);
}

String? ipv4Prefix24(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  return '${parts[0]}.${parts[1]}.${parts[2]}';
}

/// Probes the current IPv4 subnet for hosts with TCP [port] open (default
/// 9100). Cheap Wi-Fi thermal printers listen there. This phone/PC's own
/// addresses are skipped so they never show up as a printer.
Future<List<NetworkPrinterAddress>> scanNetworkPrinters({
  int port = NetworkPrinterAddress.defaultPort,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  final plan = lanScanPlan([
    for (final iface in interfaces)
      (name: iface.name, addresses: iface.addresses),
  ]);
  final prefix = plan.prefix;
  if (prefix == null) return const [];

  final found = <NetworkPrinterAddress>[];
  const batch = 32;
  for (var start = 1; start <= 254; start += batch) {
    final end = start + batch - 1 > 254 ? 254 : start + batch - 1;
    final probed = await Future.wait([
      for (var i = start; i <= end; i++)
        if (!plan.skip.contains('$prefix.$i')) _probe('$prefix.$i', port),
    ]);
    for (final hit in probed) {
      if (hit != null) found.add(hit);
    }
  }
  return found;
}

Future<NetworkPrinterAddress?> _probe(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 700),
    );
    socket.destroy();
    return NetworkPrinterAddress(host, port: port);
  } catch (_) {
    return null;
  }
}
