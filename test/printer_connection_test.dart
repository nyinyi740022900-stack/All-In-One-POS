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
    test('uses the first real IPv4 /24 and skips this device', () {
      final plan = lanScanPlan([
        InternetAddress.loopbackIPv4,
        InternetAddress('192.168.1.42'),
        InternetAddress('10.0.0.5'),
      ]);
      expect(plan.prefix, '192.168.1');
      expect(plan.skip, {'192.168.1.42', '10.0.0.5'});
    });

    test('empty or loopback-only yields no prefix', () {
      final plan = lanScanPlan([InternetAddress.loopbackIPv4]);
      expect(plan.prefix, isNull);
      expect(plan.skip, isEmpty);
    });
  });
}
