import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/ble_constants.dart';

class BluetoothController extends GetxController {
  static const bool _verboseBleLogs = true;
  static const Duration kScanTimeout = Duration(seconds: 15);

  static final Guid _gattService = Guid(kServiceUuid);
  static final Guid _gattCharacteristic = Guid(kCharacteristicUuid);

  final devices = <BluetoothDevice>[].obs;
  final selectedDevice = Rxn<BluetoothDevice>();
  final sliderValue = 0.0.obs;
  final receivedData = ''.obs;
  final isConnected = false.obs;
  final isScanning = false.obs;
  final adapterState = BluetoothAdapterState.unknown.obs;
  final scanSessionDebug = ''.obs;

  BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  final Set<String> _seenScanIds = <String>{};
  final StringBuffer _scanSessionBuffer = StringBuffer();
  bool _scanDebugRecording = false;
  Timer? _scanDebugEndTimer;

  void _bleLog(String message) {
    if (!kDebugMode || !_verboseBleLogs) return;
    final ts = DateTime.now().toIso8601String();
    print('[$ts][BLE] $message');
  }

  void _scanDebugAppend(String message) {
    final ts = DateTime.now().toIso8601String();
    _scanSessionBuffer.writeln('[$ts] $message');
    scanSessionDebug.value = _scanSessionBuffer.toString();
  }

  void _endScanDebugSession(String reason) {
    if (!_scanDebugRecording) return;
    _scanDebugAppend('=== SCAN SESSION END ($reason) ===');
    _scanDebugRecording = false;
    _scanDebugEndTimer?.cancel();
    _scanDebugEndTimer = null;
  }

  /// Dropdown label: **advName** only when present; else platformName; else MAC.
  String deviceLabel(BluetoothDevice d) {
    final adv = d.advName.trim();
    if (adv.isNotEmpty) return adv;
    final plat = d.platformName.trim();
    if (plat.isNotEmpty) return plat;
    return d.remoteId.str;
  }

  /// [DropdownButton] items must match [selectedDevice] instance from [devices].
  BluetoothDevice? dropdownValue() {
    final sel = selectedDevice.value;
    if (sel == null) return null;
    for (final d in devices) {
      if (d.remoteId == sel.remoteId) return d;
    }
    return null;
  }

  Future<void> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    _bleLog(
      'permissions: ${statuses.map((k, v) => MapEntry(k.toString(), v.toString()))}',
    );
  }

  Future<void> initBluetooth() async {
    _bleLog('initBluetooth()');
    await requestPermissions();

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _bleLog('Bluetooth LE not supported on this device');
      return;
    }
    _bleLog(
      'supported: $supported, adapterStateNow: ${FlutterBluePlus.adapterStateNow}',
    );

    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (isClosed) return;
      adapterState.value = state;
      _bleLog('adapterState: $state');
      if (state == BluetoothAdapterState.on) {
        startScan().catchError((Object e, StackTrace st) {
          _bleLog('startScan after adapter on: $e');
        });
      }
    });

    _scanResultsSubscription = FlutterBluePlus.onScanResults.listen((results) {
      if (isClosed) return;
      _bleLog('scanResults: ${results.length} results');

      if (_scanDebugRecording) {
        _scanDebugAppend('scanResults batch: ${results.length}');
      }

      for (final r in results) {
        final id = r.device.remoteId.str;
        if (_seenScanIds.add(id)) {
          final foundLine =
              'FOUND id=$id '
              'platformName="${r.device.platformName}" advName="${r.device.advName}" '
              'rssi=${r.rssi} '
              'connectable=${r.advertisementData.connectable} '
              'serviceUuids=${r.advertisementData.serviceUuids.map((e) => e.str).toList()}';
          _bleLog(foundLine);
          if (_scanDebugRecording) {
            _scanDebugAppend(foundLine);
          }
        }
      }

      final byId = <String, BluetoothDevice>{};
      for (final r in results) {
        byId[r.device.remoteId.str] = r.device;
      }
      final list = byId.values.toList()
        ..sort(
          (a, b) => deviceLabel(
            a,
          ).toLowerCase().compareTo(deviceLabel(b).toLowerCase()),
        );
      devices.assignAll(list);
    });

    _scanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (isClosed) return;
      isScanning.value = scanning;
      _bleLog('isScanning: $scanning');
    });

    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      try {
        _bleLog('turnOn() requested');
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _bleLog('Could not turn Bluetooth on: $e');
      }
    } else {
      await startScan();
    }
  }

  Future<void> startScan() async {
    if (adapterState.value != BluetoothAdapterState.on) return;

    _scanDebugEndTimer?.cancel();
    _scanDebugEndTimer = null;
    _scanSessionBuffer.clear();
    scanSessionDebug.value = '';
    _scanDebugRecording = true;
    _scanDebugAppend('=== SCAN SESSION START ===');
    _scanDebugAppend('adapterState=${adapterState.value}');
    _scanDebugAppend('platform=$defaultTargetPlatform');
    _scanDebugAppend(
      'scanSettings: timeout=${kScanTimeout.inSeconds}s continuousUpdates=true androidUsesFineLocation=true',
    );

    try {
      _bleLog('_startScan() (${kScanTimeout.inSeconds}s timeout)');
      _seenScanIds.clear();
      await FlutterBluePlus.startScan(
        timeout: kScanTimeout,
        continuousUpdates: true,
        androidUsesFineLocation: true,
      );
      _scanDebugEndTimer = Timer(kScanTimeout, () {
        if (isClosed) return;
        _endScanDebugSession('duration elapsed (${kScanTimeout.inSeconds}s)');
      });
    } catch (e) {
      _bleLog('startScan error: $e');
      _scanDebugAppend('startScan error: $e');
      _endScanDebugSession('startScan failed');
    }
  }

  void onDeviceSelected(BluetoothDevice? d) {
    selectedDevice.value = d;
    if (d != null) {
      _bleLog(
        'selectedDevice: id=${d.remoteId.str} platformName="${d.platformName}" advName="${d.advName}"',
      );
    }
  }

  Future<void> _setupGatt(BluetoothDevice device) async {
    _bleLog(
      'discoverServices() on id=${device.remoteId.str} label="${deviceLabel(device)}"',
    );
    await device.discoverServices();
    _bleLog('services discovered: ${device.servicesList.length}');

    BluetoothCharacteristic? target;
    for (final service in device.servicesList) {
      _bleLog(
        'service: ${service.uuid.str}, chars=${service.characteristics.length}',
      );
      if (service.uuid != _gattService) continue;
      for (final c in service.characteristics) {
        _bleLog('  char: ${c.uuid.str} props=${c.properties}');
        if (c.uuid == _gattCharacteristic) {
          target = c;
          break;
        }
      }
      if (target != null) break;
    }

    if (target == null) {
      throw FlutterBluePlusException(
        ErrorPlatform.fbp,
        'setupGatt',
        FbpErrorCode.characteristicNotFound.index,
        'Service $kServiceUuid or characteristic $kCharacteristicUuid not found',
      );
    }

    _commandCharacteristic = target;
    _bleLog(
      'command characteristic ready: ${target.uuid.str} props=${target.properties}',
    );
    await _subscribeNotificationsIfNeeded(target);
  }

  Future<void> _subscribeNotificationsIfNeeded(
    BluetoothCharacteristic ch,
  ) async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    final props = ch.properties;
    if (!props.notify && !props.indicate) {
      _bleLog(
        'Characteristic has no notify/indicate; console will only show local writes if any.',
      );
      return;
    }

    _bleLog('enabling notifications for char=${ch.uuid.str}');
    await ch.setNotifyValue(true);
    _notifySubscription = ch.onValueReceived.listen((value) {
      if (isClosed) return;
      final msg = utf8.decode(value, allowMalformed: true);
      receivedData.value += msg;
      _bleLog('notify bytes=${value.length} decoded="$msg" raw=$value');
    });
  }

  void _listenForDisconnect(BluetoothDevice device) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        tearDownSession();
      }
    });
  }

  void tearDownSession() {
    _bleLog('_tearDownSession()');
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _commandCharacteristic = null;
    if (!isClosed) {
      isConnected.value = false;
    }
  }

  Future<void> connect() async {
    if (selectedDevice.value == null) return;
    if (adapterState.value != BluetoothAdapterState.on) {
      _bleLog('connect() blocked: adapterState=${adapterState.value}');
      return;
    }

    try {
      _bleLog('stopScan() before connect');
      _scanDebugEndTimer?.cancel();
      _scanDebugEndTimer = null;
      if (_scanDebugRecording) {
        _scanDebugAppend('(stopping scan for connection attempt)');
        _endScanDebugSession('connect requested');
      }
      await FlutterBluePlus.stopScan();
      final device = selectedDevice.value!;
      _bleLog(
        'connect() -> id=${device.remoteId.str} platformName="${device.platformName}" advName="${device.advName}"',
      );

      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 35),
        mtu: null,
      );
      _bleLog('connected: ${device.isConnected}');

      await _setupGatt(device);
      _listenForDisconnect(device);

      if (!isClosed) isConnected.value = true;
      _bleLog('READY (isConnected=true)');
    } on FlutterBluePlusException catch (e) {
      _bleLog('connect failed (FlutterBluePlusException): $e');
      tearDownSession();
      try {
        await selectedDevice.value?.disconnect();
      } catch (_) {}
    } catch (e) {
      _bleLog('connect failed: $e');
      tearDownSession();
      try {
        await selectedDevice.value?.disconnect();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _bleLog('disconnect() requested');
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _commandCharacteristic = null;

    try {
      await selectedDevice.value?.disconnect();
    } catch (e) {
      _bleLog('disconnect error: $e');
    }

    if (!isClosed) isConnected.value = false;
    _bleLog('disconnected (isConnected=false)');
  }

  Future<void> sendData(String value) async {
    if (!isConnected.value || _commandCharacteristic == null) return;

    final ch = _commandCharacteristic!;
    final bytes = utf8.encode(value);
    final props = ch.properties;

    final bool withoutResponse = props.writeWithoutResponse && !props.write;

    try {
      _bleLog(
        'write -> char=${ch.uuid.str} withoutResponse=$withoutResponse value="$value" bytes=$bytes',
      );
      await ch.write(bytes, withoutResponse: withoutResponse);
      _bleLog('write OK');
    } catch (e) {
      _bleLog('write failed: $e');
    }
  }

  Future<void> copyScanDebugToClipboard() async {
    final text = scanSessionDebug.value.trim();
    if (text.isEmpty) {
      Get.snackbar(
        '',
        'No scan debug yet — tap Scan BLE first',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    Get.snackbar(
      '',
      'Scan debug copied',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onInit() {
    super.onInit();
    initBluetooth().catchError((Object e, StackTrace st) {
      _bleLog('initBluetooth: $e');
    });
  }

  @override
  void onClose() {
    _scanDebugEndTimer?.cancel();
    _scanResultsSubscription?.cancel();
    _adapterSubscription?.cancel();
    _scanningSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();

    // Stop scan first, then disconnect — safer on Android stacks than parallel futures.
    FlutterBluePlus.stopScan().catchError((Object e, _) {
      _bleLog('stopScan on close: $e');
    }).whenComplete(() {
      final dev = selectedDevice.value;
      if (dev?.isConnected ?? false) {
        dev!
            .disconnect()
            .catchError((Object e, _) {
              _bleLog('disconnect on close: $e');
            });
      }
    });

    super.onClose();
  }
}
