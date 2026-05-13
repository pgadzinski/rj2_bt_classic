import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/bluetooth_controller.dart';

/// Full-screen scan + BLE log from [BluetoothController].
class BleDebugPage extends GetView<BluetoothController> {
  const BleDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug (scan + BLE)'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Clear list',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => controller.clearUnifiedDebug(),
          ),
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy),
            onPressed: () => controller.copyUnifiedDebugToClipboard(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Obx(() {
            final text = controller.unifiedDebugDisplay();
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
