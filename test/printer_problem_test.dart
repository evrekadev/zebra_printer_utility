import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebrautil/zebra_printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ZebraPrinter printerAnswering(Future<Object?> Function() answer) {
    final printer = ZebraPrinter('test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printer.channel, (call) {
      expect(call.method, 'printerStatus');
      return answer();
    });
    return printer;
  }

  test('paperOut and headOpen are problems', () async {
    expect(await printerAnswering(() async => 'paperOut').printerProblem(),
        PrinterProblem.paperOut);
    expect(await printerAnswering(() async => 'headOpen').printerProblem(),
        PrinterProblem.headOpen);
  });

  test('ready, no answer and an unknown word are no problem', () async {
    expect(
        await printerAnswering(() async => 'ready').printerProblem(), isNull);
    expect(await printerAnswering(() async => null).printerProblem(), isNull);
    expect(
        await printerAnswering(() async => 'paused').printerProblem(), isNull);
  });

  test('a platform error is no problem', () async {
    final printer =
        printerAnswering(() async => throw PlatformException(code: 'x'));
    expect(await printer.printerProblem(), isNull);
  });

  test('a silent printer is no problem once the timeout passes', () async {
    final printer =
        printerAnswering(() => Future.delayed(const Duration(seconds: 1)));
    expect(
        await printer.printerProblem(timeout: const Duration(milliseconds: 50)),
        isNull);
  });
}
