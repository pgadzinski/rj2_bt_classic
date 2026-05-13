import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'bindings/bluetooth_binding.dart';
import 'pages/bluetooth_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'RJ2',
      debugShowCheckedModeBanner: false,
      initialBinding: BluetoothBinding(),
      home: const BluetoothPage(),
    );
  }
}
