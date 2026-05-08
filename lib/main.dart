import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Custom GATT service exposed by the peripheral (Arduino / BLE module).
const String kServiceUuid = '12345678-1234-1234-1234-1234567890ab';

/// Writable (and optionally notifiable) characteristic for commands and telemetry.
const String kCharacteristicUuid = 'abcd1234-5678-1234-5678-abcdef123456';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BluetoothPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  static const bool _verboseBleLogs = true;

  void _bleLog(String message) {
    if (!kDebugMode || !_verboseBleLogs) return;
    final ts = DateTime.now().toIso8601String();
    print('[$ts][BLE] $message');
  }

  // --- BLE UUIDs as [Guid] for comparisons against discovered services/chars ---
  static final Guid _gattService = Guid(kServiceUuid);
  static final Guid _gattCharacteristic = Guid(kCharacteristicUuid);

  /// Devices seen during the current / last scan (deduped by [BluetoothDevice.remoteId]).
  List<BluetoothDevice> devices = [];

  BluetoothDevice? selectedDevice;

  /// After GATT setup, holds the TX characteristic used for `S1:angle` writes.
  BluetoothCharacteristic? _commandCharacteristic;

  double sliderValue = 0;

  bool isConnected = false;
  String receivedData = '';

  /// True while the stack reports an active scan.
  bool isScanning = false;

  /// Host adapter on/off/unknown — drives permission and scan behavior.
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;

  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  /// Helps reduce scan log spam while still printing “new” devices.
  final Set<String> _seenScanIds = <String>{};

  @override
  void initState() {
    super.initState();
    initBluetooth();
  }

  /// Android / runtime BLE-related permissions (location still commonly required for scan on older stacks).
  Future<void> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    _bleLog('permissions: ${statuses.map((k, v) => MapEntry(k.toString(), v.toString()))}');
  }

  String _deviceLabel(BluetoothDevice d) {
    if (d.platformName.isNotEmpty) return d.platformName;
    if (d.advName.isNotEmpty) return d.advName;
    return d.remoteId.str;
  }

  /// [DropdownButton] must reference the same instance as in [items], so resolve by [remoteId].
  BluetoothDevice? _dropdownValue() {
    if (selectedDevice == null) return null;
    for (final d in devices) {
      if (d.remoteId == selectedDevice!.remoteId) return d;
    }
    return null;
  }

  /// Subscribe to adapter state, scan results, and scanning flag; kick off first scan when radio is on.
  Future<void> initBluetooth() async {
    _bleLog('initBluetooth()');
    await requestPermissions();

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      _bleLog('Bluetooth LE not supported on this device');
      return;
    }
    _bleLog('supported: $supported, adapterStateNow: ${FlutterBluePlus.adapterStateNow}');

    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() => adapterState = state);
      _bleLog('adapterState: $state');
      if (state == BluetoothAdapterState.on) {
        unawaited(_startScan());
      }
    });

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      _bleLog('scanResults: ${results.length} results');

      // Print each newly-seen peripheral with as much info as FlutterBluePlus provides.
      for (final r in results) {
        final id = r.device.remoteId.str;
        if (_seenScanIds.add(id)) {
          _bleLog(
            'FOUND id=$id '
            'platformName="${r.device.platformName}" advName="${r.device.advName}" '
            'rssi=${r.rssi} '
            'connectable=${r.advertisementData.connectable} '
            'serviceUuids=${r.advertisementData.serviceUuids.map((e) => e.str).toList()}',
          );
        }
      }

      final byId = <String, BluetoothDevice>{};
      for (final r in results) {
        byId[r.device.remoteId.str] = r.device;
      }
      final list = byId.values.toList()
        ..sort((a, b) => _deviceLabel(a).toLowerCase().compareTo(_deviceLabel(b).toLowerCase()));
      setState(() => devices = list);
    });

    _scanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (!mounted) return;
      setState(() => isScanning = scanning);
      _bleLog('isScanning: $scanning');
    });

    // Turn radio on (Android); no-op / unsupported elsewhere.
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      try {
        _bleLog('turnOn() requested');
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _bleLog('Could not turn Bluetooth on: $e');
      }
    } else {
      await _startScan();
    }
  }

  /// Starts a finite scan so the dropdown fills with nearby peripherals.
  Future<void> _startScan() async {
    if (adapterState != BluetoothAdapterState.on) return;
    try {
      _bleLog('_startScan() (15s timeout)');
      _seenScanIds.clear();
      // Scan all peripherals; the custom service UUID is matched after connect in [_setupGatt].
      // To narrow results, pass `withServices: [_gattService]` if your board advertises that UUID.
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _bleLog('startScan error: $e');
    }
  }

  /// Public so the UI can offer a manual “Scan again” action.
  Future<void> scanDevices() => _startScan();

  /// Finds the command characteristic, enables notifications when available, and wires disconnect cleanup.
  Future<void> _setupGatt(BluetoothDevice device) async {
    _bleLog('discoverServices() on id=${device.remoteId.str} label="${_deviceLabel(device)}"');
    await device.discoverServices();
    _bleLog('services discovered: ${device.servicesList.length}');

    BluetoothCharacteristic? target;
    for (final service in device.servicesList) {
      _bleLog('service: ${service.uuid.str}, chars=${service.characteristics.length}');
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
    _bleLog('command characteristic ready: ${target.uuid.str} props=${target.properties}');
    await _subscribeNotificationsIfNeeded(target);
  }

  /// Subscribes to NOTIFY / INDICATE so the console can show remote data when the firmware supports it.
  Future<void> _subscribeNotificationsIfNeeded(BluetoothCharacteristic ch) async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    final props = ch.properties;
    if (!props.notify && !props.indicate) {
      _bleLog('Characteristic has no notify/indicate; console will only show local writes if any.');
      return;
    }

    _bleLog('enabling notifications for char=${ch.uuid.str}');
    await ch.setNotifyValue(true);
    _notifySubscription = ch.onValueReceived.listen((value) {
      if (!mounted) return;
      final msg = utf8.decode(value, allowMalformed: true);
      setState(() => receivedData += msg);
      _bleLog('notify bytes=${value.length} decoded="$msg" raw=$value');
    });
  }

  void _listenForDisconnect(BluetoothDevice device) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _tearDownSession();
      }
    });
  }

  /// Clears GATT state and subscriptions after a drop or explicit disconnect.
  void _tearDownSession() {
    _bleLog('_tearDownSession()');
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _commandCharacteristic = null;
    if (mounted) {
      setState(() => isConnected = false);
    }
  }

  /// Connect, discover service/characteristic, then mark ready for writes.
  Future<void> connect() async {
    if (selectedDevice == null) return;
    if (adapterState != BluetoothAdapterState.on) {
      _bleLog('connect() blocked: adapterState=$adapterState');
      return;
    }

    try {
      _bleLog('stopScan() before connect');
      await FlutterBluePlus.stopScan();
      final device = selectedDevice!;
      _bleLog('connect() -> id=${device.remoteId.str} platformName="${device.platformName}" advName="${device.advName}"');

      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 35),
        mtu: null,
      );
      _bleLog('connected: ${device.isConnected}');

      await _setupGatt(device);
      _listenForDisconnect(device);

      if (mounted) setState(() => isConnected = true);
      _bleLog('READY (isConnected=true)');
    } on FlutterBluePlusException catch (e) {
      _bleLog('connect failed (FlutterBluePlusException): $e');
      _tearDownSession();
      try {
        await selectedDevice?.disconnect();
      } catch (_) {}
    } catch (e) {
      _bleLog('connect failed: $e');
      _tearDownSession();
      try {
        await selectedDevice?.disconnect();
      } catch (_) {}
    }
  }

  /// Disconnect from the peripheral and release notify subscription.
  Future<void> disconnect() async {
    _bleLog('disconnect() requested');
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _commandCharacteristic = null;

    try {
      await selectedDevice?.disconnect();
    } catch (e) {
      _bleLog('disconnect error: $e');
    }

    if (mounted) setState(() => isConnected = false);
    _bleLog('disconnected (isConnected=false)');
  }

  /// Sends `S1:<angle>\\n` over BLE write (same semantics as before: one slider → servo 1).
  Future<void> sendData(String value) async {
    if (!isConnected || _commandCharacteristic == null) return;

    final ch = _commandCharacteristic!;
    final bytes = utf8.encode(value);
    final props = ch.properties;

    // Prefer write-with-response when available for reliability.
    final bool withoutResponse = props.writeWithoutResponse && !props.write;

    try {
      _bleLog('write -> char=${ch.uuid.str} withoutResponse=$withoutResponse value="$value" bytes=$bytes');
      await ch.write(bytes, withoutResponse: withoutResponse);
      _bleLog('write OK');
    } catch (e) {
      _bleLog('write failed: $e');
    }
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _adapterSubscription?.cancel();
    _scanningSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    unawaited(FlutterBluePlus.stopScan());
    if (selectedDevice?.isConnected ?? false) {
      unawaited(selectedDevice!.disconnect());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adapterOk = adapterState == BluetoothAdapterState.on;
    final statusColor = !adapterOk
        ? Colors.orange.shade100
        : isConnected
            ? Colors.green.shade100
            : Colors.red.shade100;
    final statusIconColor = !adapterOk
        ? Colors.orange
        : isConnected
            ? Colors.green
            : Colors.red;
    final statusText = !adapterOk
        ? 'ADAPTER OFF'
        : isConnected
            ? 'CONNECTED'
            : 'DISCONNECTED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('RJ2'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status: adapter + GATT session
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      !adapterOk
                          ? Icons.bluetooth_disabled
                          : isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                      color: statusIconColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusIconColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // Scan + device picker
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (!adapterOk || isScanning) ? null : () => scanDevices(),
                      icon: isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.radar),
                      label: Text(isScanning ? 'Scanning…' : 'Scan BLE'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<BluetoothDevice>(
                  hint: const Text('Select Device'),
                  value: _dropdownValue(),
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: devices.isEmpty
                      ? []
                      : devices.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(
                              _deviceLabel(d),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                  onChanged: (d) {
                    setState(() => selectedDevice = d);
                    if (d != null) {
                      _bleLog('selectedDevice: id=${d.remoteId.str} platformName="${d.platformName}" advName="${d.advName}"');
                    }
                  },
                ),
              ),

              const SizedBox(height: 15),

              ElevatedButton.icon(
                onPressed: (!adapterOk || selectedDevice == null || isConnected) ? null : connect,
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 10),

              ElevatedButton.icon(
                onPressed: !isConnected ? null : disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 20),

              // Slider panel (unchanged behavior: set angle, send on button)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'ANGLE CONTROL',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: sliderValue,
                            min: 0,
                            max: 180,
                            divisions: 180,
                            label: sliderValue.round().toString(),
                            onChanged: (value) {
                              setState(() => sliderValue = value);
                            },
                          ),
                        ),
                        Text(
                          '${sliderValue.round()}°',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Protocol: S1:<deg>\n (S2 would be a second channel, e.g. another slider)
                        sendData('S1:${sliderValue.round()}\n');
                      },
                      child: const Text('SEND TO arduino uno R3'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),
               
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      receivedData.isEmpty ? 'Waiting for arduino uno R3 data...' : receivedData,
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
