import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  BluetoothDevice? _device;
  bool _isConnected = false;
  StreamSubscription<List<int>>? _dataSubscription;

  static const String _targetDeviceName = 'ESP32_ECG';
  static const String _ecgServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String _ecgCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  final StreamController<int> _ecgStreamController =
      StreamController<int>.broadcast();
  Stream<int> get ecgStream => _ecgStreamController.stream;
  bool get isConnected => _isConnected;

  void Function()? onDisconnected;

  Future<void> initialize() async {}

  Future<BluetoothDevice> findDevice() async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    await Future.delayed(const Duration(milliseconds: 500));

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    final seen = <String>{};
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 16)) {
      await Future.delayed(const Duration(seconds: 1));
      final results = FlutterBluePlus.lastScanResults;
      for (final result in results) {
        final name = result.device.platformName;
        final advName = result.advertisementData.advName;
        final id = result.device.remoteId.str.toLowerCase();
        seen.add(name.isNotEmpty ? name : (advName.isNotEmpty ? advName : id));
        if (name.contains(_targetDeviceName) ||
            advName.contains(_targetDeviceName) ||
            id == '0c:dc:7e:61:03:e6') {
          await FlutterBluePlus.stopScan();
          return result.device;
        }
      }
    }

    await FlutterBluePlus.stopScan();
    throw Exception('ESP32_ECG not found. Discovered: ${seen.isEmpty ? "none" : seen.join(", ")}');
  }

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    try {
      await device.connect();
      _isConnected = true;

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          onDisconnected?.call();
        }
      });

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == _ecgServiceUuid.toLowerCase() ||
            service.uuid.toString().toLowerCase().contains('ffe0')) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == _ecgCharUuid.toLowerCase() ||
                characteristic.uuid.toString().toLowerCase().contains('ffe1')) {
              await characteristic.setNotifyValue(true);
              _dataSubscription = characteristic.onValueReceived.listen(
                (data) => _parseEcgData(data),
              );
              return;
            }
          }
        }
      }
      throw Exception('ECG characteristic not found on ESP32_ECG');
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  void _parseEcgData(List<int> data) {
    for (var i = 0; i + 1 < data.length; i += 2) {
      final value = (data[i] << 8) | data[i + 1];
      _ecgStreamController.add(value);
    }
  }

  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _isConnected = false;
    await _device?.disconnect();
    _device = null;
  }

  void dispose() {
    _dataSubscription?.cancel();
    _ecgStreamController.close();
  }
}
