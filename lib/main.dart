import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final FlutterBluetoothClassic bluetooth = FlutterBluetoothClassic();

  // Servo angles derived from joystick
  double s1Angle = 90;
  double s2Angle = 90;

  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;

  bool isConnected = false;
  bool isConnecting = false;
  bool isSendingContinuous = false;
  String receivedData = "";
  final ScrollController _consoleScroll = ScrollController();

  StreamSubscription? dataSubscription;

  @override
  void initState() {
    super.initState();
    initBluetooth();
  }

  // 🔐 Runtime Permissions
  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  // 🔵 Init Bluetooth
  Future<void> initBluetooth() async {
    await requestPermissions();

    bool isSupported = await bluetooth.isBluetoothSupported();
    if (!isSupported) {
      _showSnack("Bluetooth is not supported on this device.");
      return;
    }

    bool isEnabled = await bluetooth.isBluetoothEnabled();
    if (!isEnabled) await bluetooth.enableBluetooth();

    try {
      final paired = await bluetooth.getPairedDevices();
      setState(() => devices = paired);
      if (devices.isEmpty) {
        _showSnack("No paired devices found. Pair the HC-05 in Bluetooth settings first.");
      }
    } catch (e) {
      _showSnack("Could not load paired devices: $e");
    }
  }

  // 🔗 Connect
  Future<void> connect() async {
    if (selectedDevice == null) {
      _showSnack("Please select a device first.");
      return;
    }
    setState(() => isConnecting = true);
    try {
      bool connected = await bluetooth.connect(selectedDevice!.address);
      if (connected) {
        setState(() => isConnected = true);
        dataSubscription = bluetooth.onDataReceived.listen((data) {
          setState(() => receivedData += data.asString());
        });
      } else {
        _showSnack("Failed to connect. Make sure the HC-05 is powered on.");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => isConnecting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  // 📤 Send data
  Future<void> sendData(String value) async {
    if (!isConnected) return;
    await bluetooth.sendString(value);
  }

  // 🕹 Joystick moved
  void _onJoystickMoved(StickDragDetails details) {
    // Y: -1 = up (180°), 1 = down (0°) → base angle for both servos
    final baseAngle = 90 - (details.y * 90);
    // X: -1 = left, 1 = right → tilt offset between servos (max ±45°)
    final tiltOffset = details.x * 45;

    setState(() {
      s1Angle = (baseAngle - tiltOffset).clamp(0, 180);
      s2Angle = (baseAngle + tiltOffset).clamp(0, 180);
    });
  }

  // 🔁 Send Continuous
  void toggleContinuous() {
    if (isSendingContinuous) {
      setState(() => isSendingContinuous = false);
    } else {
      setState(() => isSendingContinuous = true);
      _continuousLoop();
    }
  }

  Future<void> _continuousLoop() async {
    while (isSendingContinuous && isConnected) {
      final s1 = s1Angle.round();
      final s2 = s2Angle.round();
      await sendData("S1:$s1\n");
      await sendData("S2:$s2\n");
      setState(() => receivedData += "Sent → S1:$s1°  S2:$s2°\n");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_consoleScroll.hasClients) {
          _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
        }
      });
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // 🔌 Disconnect
  Future<void> disconnect() async {
    await bluetooth.disconnect();
    dataSubscription?.cancel();
    setState(() {
      isConnected = false;
      isSendingContinuous = false;
    });
  }

  @override
  void dispose() {
    dataSubscription?.cancel();
    _consoleScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RJ2"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // 🔵 STATUS CARD
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isConnected ? "CONNECTED" : "DISCONNECTED",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 📱 DEVICE SELECT
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<BluetoothDevice>(
                        hint: Text(devices.isEmpty ? "No paired devices" : "Select Device"),
                        value: selectedDevice,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: devices.map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.name, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: devices.isEmpty ? null : (d) => setState(() => selectedDevice = d),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: initBluetooth,
                    icon: const Icon(Icons.refresh),
                    tooltip: "Refresh paired devices",
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // 🔗 CONNECT / DISCONNECT
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isConnecting ? null : connect,
                      icon: isConnecting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.link),
                      label: Text(isConnecting ? "Connecting..." : "Connect"),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: disconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text("Disconnect"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 🕹 JOYSTICK + READOUTS
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "JOYSTICK CONTROL",
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Y-axis: up/down motion  •  X-axis: tilt",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    // Angle readouts
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Text("SERVO 1", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              "${s1Angle.round()}°",
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("SERVO 2", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              "${s2Angle.round()}°",
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Joystick widget
                    Joystick(
                      listener: _onJoystickMoved,
                    ),

                    const SizedBox(height: 12),

                    // Send Continuous button
                    ElevatedButton(
                      onPressed: toggleContinuous,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSendingContinuous ? Colors.orange : null,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: Text(isSendingContinuous ? "STOP Continuous" : "Send Continuous"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 📥 DATA CONSOLE
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    controller: _consoleScroll,
                    child: Text(
                      receivedData.isEmpty ? "Waiting for Arduino data..." : receivedData,
                      style: const TextStyle(color: Colors.green, fontFamily: "monospace"),
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
