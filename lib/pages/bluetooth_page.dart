import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';

import '../controllers/bluetooth_controller.dart';

class BluetoothPage extends GetView<BluetoothController> {
  const BluetoothPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RJ2'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(() {
            final c = controller;
            final adapterOk = c.adapterState.value == BluetoothAdapterState.on;
            final isConnected = c.isConnected.value;
            final isScanning = c.isScanning.value;

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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (!adapterOk || isScanning)
                            ? null
                            : () => c.startScan(),
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
                    value: c.dropdownValue(),
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: c.devices.isEmpty
                        ? []
                        : c.devices.map((d) {
                            return DropdownMenuItem(
                              value: d,
                              child: Text(
                                c.deviceLabel(d),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                    onChanged: c.onDeviceSelected,
                  ),
                ),

                const SizedBox(height: 15),

                ElevatedButton.icon(
                  onPressed:
                      (!adapterOk || c.selectedDevice.value == null || isConnected)
                          ? null
                          : c.connect,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                  ),
                ),

                const SizedBox(height: 10),

                ElevatedButton.icon(
                  onPressed: !isConnected ? null : c.disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(14),
                  ),
                ),

                const SizedBox(height: 20),

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
                              value: c.sliderValue.value,
                              min: 0,
                              max: 180,
                              divisions: 180,
                              label: c.sliderValue.value.round().toString(),
                              onChanged: (value) {
                                c.sliderValue.value = value;
                              },
                            ),
                          ),
                          Text(
                            '${c.sliderValue.value.round()}°',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () {
                          c.sendData('S1:${c.sliderValue.value.round()}\n');
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
                        c.receivedData.value.isEmpty
                            ? 'Waiting for arduino uno R3 data...'
                            : c.receivedData.value,
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Material(
                  elevation: 1,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade200,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bug_report,
                                size: 20, color: Colors.grey.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scan debug (last run — send copy if device missing)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy scan debug log',
                              icon: const Icon(Icons.copy),
                              onPressed: c.copyScanDebugToClipboard,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 120,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              child: SelectableText(
                                c.scanSessionDebug.value.isEmpty
                                    ? 'Run “Scan BLE” — timestamps, batches, and FOUND lines appear here for that run.'
                                    : c.scanSessionDebug.value.trimRight(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.35,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
