import 'package:flutter_test/flutter_test.dart';
import 'package:zebrautil/zebra_device.dart';
import 'package:zebrautil/zebra_printer.dart';

void main() {
  const address = 'AC:3F:A4:00:00:01';

  ZebraController controllerWithPrinter() => ZebraController()
    ..addPrinter(ZebraDevice(
        address: address, name: 'XXZKJ123', isWifi: false, status: ''));

  test('updatePrinterModel sets the model on the device with that address', () {
    final controller = controllerWithPrinter();
    var notified = false;
    controller.addListener(() => notified = true);

    controller.updatePrinterModel(address, 'ZQ320 Plus');

    expect(controller.printers.single.model, 'ZQ320 Plus');
    expect(notified, isTrue);
  });

  test('a following updatePrinterStatus keeps the model', () {
    final controller = controllerWithPrinter()..selectedAddress = address;
    controller.updatePrinterModel(address, 'ZQ320 Plus');

    controller.updatePrinterStatus('Connected', 'G');

    final device = controller.printers.single;
    expect(device.model, 'ZQ320 Plus');
    expect(device.status, 'Connected');
    expect(device.isConnected, isTrue);
  });

  test('updatePrinterModel ignores an unknown address', () {
    final controller = controllerWithPrinter();

    controller.updatePrinterModel('00:00:00:00:00:00', 'ZQ320 Plus');

    expect(controller.printers.single.model, isNull);
  });

  test('updatePrinterStatus does nothing when the selected device is missing',
      () {
    final controller = controllerWithPrinter()
      ..selectedAddress = '00:00:00:00:00:00';

    expect(() => controller.updatePrinterStatus('Connected', 'G'),
        returnsNormally);
    expect(controller.printers.single.status, '');
  });
}
