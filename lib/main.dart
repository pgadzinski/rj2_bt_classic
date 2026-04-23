import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

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
  int sendIntervalMs = 1000;
  String receivedData = "";
  final ScrollController _consoleScroll = ScrollController();

  // 🎙 Recording
  bool isRecording = false;
  int recordIntervalMs = 500;
  List<Map<String, dynamic>> recordedFrames = [];
  Timer? recordTimer;

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
      await Future.delayed(Duration(milliseconds: sendIntervalMs));
    }
  }

  // 🎙 Recording
  void toggleRecording() {
    if (isRecording) {
      recordTimer?.cancel();
      setState(() => isRecording = false);
      _showSnack("Recording stopped — ${recordedFrames.length} frames captured.");
    } else {
      setState(() {
        isRecording = true;
        recordedFrames = [];
      });
      recordTimer = Timer.periodic(Duration(milliseconds: recordIntervalMs), (_) {
        recordedFrames.add({
          't': DateTime.now().millisecondsSinceEpoch,
          's1': s1Angle.round(),
          's2': s2Angle.round(),
        });
        setState(() {});
      });
      _showSnack("Recording started.");
    }
  }

  Future<void> exportRecording() async {
    if (recordedFrames.isEmpty) {
      _showSnack("Nothing to export.");
      return;
    }
    final t0 = recordedFrames.first['t'] as int;
    final lines = ['elapsed_ms,s1_deg,s2_deg'];
    for (final f in recordedFrames) {
      lines.add('${f['t'] - t0},${f['s1']},${f['s2']}');
    }
    final csv = lines.join('\n');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/rj2_motion_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)], text: 'RJ2 Motion Recording');
  }

  void clearRecording() {
    recordTimer?.cancel();
    setState(() {
      isRecording = false;
      recordedFrames = [];
    });
  }

  // 🔌 Disconnect
  Future<void> disconnect() async {
    await bluetooth.disconnect();
    dataSubscription?.cancel();
    recordTimer?.cancel();
    setState(() {
      isConnected = false;
      isSendingContinuous = false;
      isRecording = false;
    });
  }

  @override
  void dispose() {
    dataSubscription?.cancel();
    recordTimer?.cancel();
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
        child: SingleChildScrollView(
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

                    // ⏱ SEND INTERVAL
                    Row(
                      children: [
                        const Text("INTERVAL", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Expanded(
                          child: Slider(
                            value: sendIntervalMs.toDouble(),
                            min: 50,
                            max: 2000,
                            divisions: 39,
                            onChanged: (val) => setState(() => sendIntervalMs = val.round()),
                          ),
                        ),
                        SizedBox(
                          width: 72,
                          child: Text(
                            "${sendIntervalMs}ms  ${(1000 / sendIntervalMs).toStringAsFixed(1)}Hz",
                            style: const TextStyle(fontSize: 11, color: Colors.blue),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

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

              // 🎙 MOTION RECORDER
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRecording ? Colors.red.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: isRecording ? Border.all(color: Colors.red.shade300) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("MOTION RECORDER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                        if (isRecording)
                          Row(children: [
                            const Icon(Icons.circle, color: Colors.red, size: 10),
                            const SizedBox(width: 4),
                            Text("${recordedFrames.length} frames", style: const TextStyle(fontSize: 11, color: Colors.red)),
                          ])
                        else if (recordedFrames.isNotEmpty)
                          Text("${recordedFrames.length} frames", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Record interval slider
                    Row(
                      children: [
                        const Text("REC INTERVAL", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Expanded(
                          child: Slider(
                            value: recordIntervalMs.toDouble(),
                            min: 100,
                            max: 2000,
                            divisions: 19,
                            onChanged: isRecording ? null : (val) => setState(() => recordIntervalMs = val.round()),
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            "${recordIntervalMs}ms",
                            style: const TextStyle(fontSize: 11, color: Colors.blue),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: toggleRecording,
                            icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
                            label: Text(isRecording ? "STOP" : "RECORD"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRecording ? Colors.red : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: recordedFrames.isNotEmpty && !isRecording ? exportRecording : null,
                            icon: const Icon(Icons.upload_file),
                            label: const Text("EXPORT"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: recordedFrames.isNotEmpty && !isRecording ? clearRecording : null,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: "Clear recording",
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 📥 DATA CONSOLE
              SizedBox(
                height: 180,
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
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
