import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/printing/network_transport.dart';
import 'package:mm_pos/features/printing/printer_connection.dart';

void main() {
  group('NetworkPrinterAddress.tryParse', () {
    test('bare IPv4 uses port 9100', () {
      final parsed = NetworkPrinterAddress.tryParse('192.168.1.100');
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.100');
      expect(parsed.port, 9100);
      expect(parsed.encoded, '192.168.1.100');
    });

    test('host:port is round-tripped', () {
      final parsed = NetworkPrinterAddress.tryParse('10.0.0.8:9100');
      expect(parsed!.encoded, '10.0.0.8');
      final custom = NetworkPrinterAddress.tryParse('10.0.0.8:9101');
      expect(custom!.encoded, '10.0.0.8:9101');
      expect(custom.port, 9101);
    });

    test('trims whitespace', () {
      expect(
        NetworkPrinterAddress.tryParse('  192.168.0.5  ')!.host,
        '192.168.0.5',
      );
    });

    test('rejects empty, spaces, and illegal ports', () {
      expect(NetworkPrinterAddress.tryParse(''), isNull);
      expect(NetworkPrinterAddress.tryParse('   '), isNull);
      expect(NetworkPrinterAddress.tryParse('192.168.1.1 extra'), isNull);
      expect(NetworkPrinterAddress.tryParse('host:0'), isNull);
      expect(NetworkPrinterAddress.tryParse('host:99999'), isNull);
    });
  });

  group('printerConnectionFromStorage', () {
    test('reads stored names and defaults missing values to bluetooth', () {
      expect(
        printerConnectionFromStorage('network'),
        PrinterConnection.network,
      );
      expect(printerConnectionFromStorage('usb'), PrinterConnection.usb);
      expect(
        printerConnectionFromStorage('bluetooth'),
        PrinterConnection.bluetooth,
      );
      expect(printerConnectionFromStorage(null), PrinterConnection.bluetooth);
      expect(printerConnectionFromStorage('nope'), PrinterConnection.bluetooth);
    });
  });

  group('lanScanPlan', () {
    test('prefers the Wi-Fi interface over cellular', () {
      final plan = lanScanPlan([
        (
          name: 'pdp_ip0',
          addresses: [InternetAddress('10.44.12.9')],
        ),
        (
          name: 'en0',
          addresses: [InternetAddress('192.168.1.42')],
        ),
      ]);
      expect(plan.prefix, '192.168.1');
      // The phone's own cellular address is skipped as a candidate too.
      expect(plan.skip, {'10.44.12.9', '192.168.1.42'});
    });

    test('skips VPN tunnels', () {
      final plan = lanScanPlan([
        (
          name: 'utun3',
          addresses: [InternetAddress('10.8.0.2')],
        ),
        (
          name: 'wlan0',
          addresses: [InternetAddress('192.168.4.7')],
        ),
      ]);
      expect(plan.prefix, '192.168.4');
    });

    test('falls back to any non-cellular IPv4 when no lan-shaped name', () {
      final plan = lanScanPlan([
        (
          name: 'something0',
          addresses: [InternetAddress('192.168.9.5')],
        ),
      ]);
      expect(plan.prefix, '192.168.9');
    });

    test('empty or loopback-only yields no prefix', () {
      final plan = lanScanPlan([
        (name: 'lo0', addresses: [InternetAddress.loopbackIPv4]),
      ]);
      expect(plan.prefix, isNull);
      expect(plan.skip, isEmpty);
    });
  });
}
