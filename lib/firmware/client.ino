#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ESP32Servo.h>

#define SERVO1_PIN 18
#define SERVO2_PIN 19

Servo servo1;
Servo servo2;

// BLE UUIDs
#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-1234-5678-abcdef123456"
// ── BLE log (session) ──
// [2026-05-13T00:30:39.341819][BLE] selectedDevice: id=1C:C3:AB:C2:AD:DA platformName="ESP32-LED" advName="RJ2_BLE"
// [2026-05-13T00:30:43.494427][BLE] stopScan() before connect
// [2026-05-13T00:30:43.619005][BLE] connect() -> id=1C:C3:AB:C2:AD:DA platformName="ESP32-LED" advName="RJ2_BLE"
// [2026-05-13T00:30:43.961901][BLE] connected: true
// [2026-05-13T00:30:44.245367][BLE] GATT setup START id=1C:C3:AB:C2:AD:DA label="RJ2_BLE"
// [2026-05-13T00:30:44.245553][BLE] discoverServices attempt 1/3
// [2026-05-13T00:30:44.324305][BLE] services discovered: 3
// [2026-05-13T00:30:44.547103][BLE] service: 1800, chars=2
// [2026-05-13T00:30:44.548400][BLE] service: 1801, chars=1
// [2026-05-13T00:30:44.548877][BLE] service: 6e400001-b5a3-f393-e0a9-e50e24dcca9e, chars=2
// [2026-05-13T00:30:44.549164][BLE] characteristics scanned: 5
// [2026-05-13T00:30:44.549316][BLE] GATT setup FAILED: Service 12345678-1234-1234-1234-1234567890ab or characteristic abcd1234-5678-1234-5678-abcdef123456 not found
// [2026-05-13T00:30:44.567865][BLE] connect failed (FlutterBluePlusException): FlutterBluePlusException | setupGatt | fbp-code: 8 | Service 12345678-1234-1234-1234-1234567890ab or characteristic abcd1234-5678-1234-5678-abcdef123456 not found
// [2026-05-13T00:30:44.568996][BLE] _tearDownSession()
BLECharacteristic *pCharacteristic;

static bool g_hasClient = false;

static void logTsPrefix() {
  Serial.print('[');
  Serial.print(millis());
  Serial.print(" ms] ");
}

static void logLine(const String &msg) {
  logTsPrefix();
  Serial.println(msg);
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    g_hasClient = true;
    logLine("BLE client CONNECTED");
  }

  void onDisconnect(BLEServer *pServer) override {
    g_hasClient = false;
    logLine("BLE client DISCONNECTED");

    // Some phones require re-advertising after disconnect.
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->start();
    logLine("Advertising restarted");
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {

  void onWrite(BLECharacteristic *pCharacteristic) {

   String cmd = pCharacteristic->getValue();

if (cmd.length() > 0) {

  cmd.trim();

  logLine("RX CMD: \"" + cmd + "\" (len=" + String(cmd.length()) + ")");

  processCommand(cmd);
}
  }

  void processCommand(String cmd) {

    if (cmd.startsWith("S1:")) {

      int angle = constrain(cmd.substring(3).toInt(), 0, 180);

      servo1.write(angle);

      String response = "S1 -> " + String(angle) + " deg";

      logLine(response);


    }
    else if (cmd.startsWith("S2:")) {

      int angle = constrain(cmd.substring(3).toInt(), 0, 180);

      servo2.write(angle);

      String response = "S2 -> " + String(angle) + " deg";

      logLine(response);

    }
    else {

      logLine("Unknown CMD: \"" + cmd + "\"");
    }
  }
};

void setup() {

  Serial.begin(115200);
  delay(200);
  logLine("Boot");

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);

  servo1.write(0);
  servo2.write(0);
  logLine("Servos attached. S1 pin=" + String(SERVO1_PIN) + ", S2 pin=" + String(SERVO2_PIN));

  BLEDevice::init("RJ2_BLE");
  logLine("BLE init. Name=RJ2_BLE");

  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  logLine("BLE server created");

  BLEService *pService = pServer->createService(SERVICE_UUID);
  logLine("Service created UUID=" + String(SERVICE_UUID));

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  logLine("Characteristic created UUID=" + String(CHARACTERISTIC_UUID));

  pCharacteristic->setCallbacks(new MyCallbacks());

  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  pAdvertising->start();

  logLine("Advertising started");
  logLine("ESP32 BLE Ready");
}

void loop() {

}