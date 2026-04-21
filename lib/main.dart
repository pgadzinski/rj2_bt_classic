// import 'package:flutter/material.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   // This widget is the root of your application.
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Flutter Demo',
//       theme: ThemeData(
//         // This is the theme of your application.
//         //
//         // TRY THIS: Try running your application with "flutter run". You'll see
//         // the application has a purple toolbar. Then, without quitting the app,
//         // try changing the seedColor in the colorScheme below to Colors.green
//         // and then invoke "hot reload" (save your changes or press the "hot
//         // reload" button in a Flutter-supported IDE, or press "r" if you used
//         // the command line to start the app).
//         //
//         // Notice that the counter didn't reset back to zero; the application
//         // state is not lost during the reload. To reset the state, use hot
//         // restart instead.
//         //
//         // This works for code too, not just values: Most code changes can be
//         // tested with just a hot reload.
//         colorScheme: .fromSeed(seedColor: Colors.deepPurple),
//       ),
//       home: const MyHomePage(title: 'Flutter Demo Home Page'),
//     );
//   }
// }
//
// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});
//
//   // This widget is the home page of your application. It is stateful, meaning
//   // that it has a State object (defined below) that contains fields that affect
//   // how it looks.
//
//   // This class is the configuration for the state. It holds the values (in this
//   // case the title) provided by the parent (in this case the App widget) and
//   // used by the build method of the State. Fields in a Widget subclass are
//   // always marked "final".
//
//   final String title;
//
//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }
//
// class _MyHomePageState extends State<MyHomePage> {
//   int _counter = 0;
//
//   void _incrementCounter() {
//     setState(() {
//       // This call to setState tells the Flutter framework that something has
//       // changed in this State, which causes it to rerun the build method below
//       // so that the display can reflect the updated values. If we changed
//       // _counter without calling setState(), then the build method would not be
//       // called again, and so nothing would appear to happen.
//       _counter++;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // This method is rerun every time setState is called, for instance as done
//     // by the _incrementCounter method above.
//     //
//     // The Flutter framework has been optimized to make rerunning build methods
//     // fast, so that you can just rebuild anything that needs updating rather
//     // than having to individually change instances of widgets.
//     return Scaffold(
//       appBar: AppBar(
//         // TRY THIS: Try changing the color here to a specific color (to
//         // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
//         // change color while the other colors stay the same.
//         backgroundColor: Theme.of(context).colorScheme.inversePrimary,
//         // Here we take the value from the MyHomePage object that was created by
//         // the App.build method, and use it to set our appbar title.
//         title: Text(widget.title),
//       ),
//       body: Center(
//         // Center is a layout widget. It takes a single child and positions it
//         // in the middle of the parent.
//         child: Column(
//           // Column is also a layout widget. It takes a list of children and
//           // arranges them vertically. By default, it sizes itself to fit its
//           // children horizontally, and tries to be as tall as its parent.
//           //
//           // Column has various properties to control how it sizes itself and
//           // how it positions its children. Here we use mainAxisAlignment to
//           // center the children vertically; the main axis here is the vertical
//           // axis because Columns are vertical (the cross axis would be
//           // horizontal).
//           //
//           // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
//           // action in the IDE, or press "p" in the console), to see the
//           // wireframe for each widget.
//           mainAxisAlignment: .center,
//           children: [
//             const Text('You have pushed the button this many times:'),
//             Text(
//               '$_counter',
//               style: Theme.of(context).textTheme.headlineMedium,
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _incrementCounter,
//         tooltip: 'Increment',
//         child: const Icon(Icons.add),
//       ),
//     );
//   }
// }

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
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
  double sliderValue = 0;
  double sliderValue2 = 0;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;

  bool isConnected = false;
  bool isConnecting = false;
  bool isSendingContinuous = false;
  String receivedData = "";

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
    if (!isEnabled) {
      await bluetooth.enableBluetooth();
    }

    try {
      final paired = await bluetooth.getPairedDevices();
      setState(() => devices = paired);

      if (devices.isEmpty) {
        _showSnack("No paired devices found. Pair the HC-05 in Android Bluetooth settings first.");
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
          String msg = data.asString();
          setState(() => receivedData += msg);
        });
      } else {
        _showSnack("Failed to connect to ${selectedDevice!.name}. Make sure the HC-05 is powered on and paired.");
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

    await bluetooth.sendString(value); // newline important
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
      await sendData("S1:${sliderValue.round()}\n");
      await sendData("S2:${sliderValue2.round()}\n");
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  // 🔌 Disconnect
  Future<void> disconnect() async {
    await bluetooth.disconnect();
    dataSubscription?.cancel();

    setState(() {
      isConnected = false;
    });
  }

  @override
  void dispose() {
    dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RJ2 - Pete"),
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

              const SizedBox(height: 15),

              // 📱 DEVICE SELECT CARD
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
                        hint: Text(
                          devices.isEmpty ? "No paired devices found" : "Select Device",
                        ),
                        value: selectedDevice,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: devices.map((d) {
                          return DropdownMenuItem(
                            value: d,
                            child: Text(
                              d.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: devices.isEmpty ? null : (d) {
                          setState(() => selectedDevice = d);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: initBluetooth,
                    icon: const Icon(Icons.refresh),
                    tooltip: "Refresh paired devices",
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // 🔗 CONNECT BUTTON
              ElevatedButton.icon(
                onPressed: isConnecting ? null : connect,
                icon: isConnecting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link),
                label: Text(isConnecting ? "Connecting..." : "Connect"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 10),

              ElevatedButton.icon(
                onPressed: disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text("Disconnect"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 20),

              // 🎚 SERVO 1 SLIDER PANEL
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [

                    const Text(
                      "SERVO 1 — ANGLE CONTROL",
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
                          "${sliderValue.round()}°",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),

                    ElevatedButton(
                      onPressed: () => sendData("S1:${sliderValue.round()}\n"),
                      child: const Text("SEND Servo 1"),
                    ),

                    const SizedBox(height: 8),

                    ElevatedButton(
                      onPressed: toggleContinuous,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSendingContinuous ? Colors.orange : null,
                      ),
                      child: Text(isSendingContinuous ? "STOP Continuous" : "Send Continuous"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // 🎚 SERVO 2 SLIDER PANEL (Pin 10)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "SERVO 2 — ANGLE CONTROL (Pin 10)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: sliderValue2,
                            min: 0,
                            max: 180,
                            divisions: 180,
                            label: sliderValue2.round().toString(),
                            onChanged: (value) {
                              setState(() => sliderValue2 = value);
                            },
                          ),
                        ),
                        Text(
                          "${sliderValue2.round()}°",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () => sendData("S2:${sliderValue2.round()}\n"),
                      child: const Text("SEND Servo 2"),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // 📥 DATA CONSOLE
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      receivedData.isEmpty
                          ? "Waiting for arduino uno R3 data..."
                          : receivedData,
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: "monospace",
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