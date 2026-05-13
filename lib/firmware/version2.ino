#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>

// ---------------------- Servo pins ----------------------
#define SERVO1_PIN 18
#define SERVO2_PIN 19

Servo servo1;
Servo servo2;

// ---------------------- BLE UUIDs ----------------------
// Keep these in sync with Flutter `kServiceUuid` / `kCharacteristicUuid`
#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-1234-5678-abcdef123456"

// Single RX/TX characteristic (write + notify)
BLECharacteristic *controlCharacteristic = nullptr;

// BLE name shown in scanner (advName)
const char *SERVER_NAME = "RJ2_BLE";

// ---------------------- State flags ----------------------
bool deviceConnected = false;

// ---------------------- Logging helpers ----------------------
static void logTsPrefix() {
  Serial.print('[');
  Serial.print(millis());
  Serial.print(" ms] ");
}

static void logLine(const String &msg) {
  logTsPrefix();
  Serial.println(msg);
}

// ---------------------- BLE callbacks ----------------------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    logLine("BLE client CONNECTED");
  }

  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    logLine("BLE client DISCONNECTED");

    // Important for some Android phones: re-start advertising immediately
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->start();
    logLine("Advertising restarted");
  }
};

class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    std::string value = pChar->getValue();
    if (value.empty()) {
      return;
    }

    String cmd = String(value.c_str());
    cmd.trim();

    logLine("RX CMD: \"" + cmd + "\" (len=" + String(cmd.length()) + ")");

    handleCommand(cmd);
  }

  void handleCommand(const String &cmd) {
    if (cmd.startsWith("S1:")) {
      int angle = constrain(cmd.substring(3).toInt(), 0, 180);
      servo1.write(angle);

      String response = "S1 -> " + String(angle) + " deg";
      logLine(response);
      sendAck(response);
    } else if (cmd.startsWith("S2:")) {
      int angle = constrain(cmd.substring(3).toInt(), 0, 180);
      servo2.write(angle);

      String response = "S2 -> " + String(angle) + " deg";
      logLine(response);
      sendAck(response);
    } else {
      String response = "Unknown CMD: \"" + cmd + "\"";
      logLine(response);
      sendAck(response);
    }
  }

  // Simple text ACK back to Flutter over same characteristic (notify)
  void sendAck(const String &message) {
    if (!deviceConnected || controlCharacteristic == nullptr) {
      return;
    }

    // You can switch this to JSON if needed later
    String payload = message;
    controlCharacteristic->setValue(
      (uint8_t *)payload.c_str(),
      payload.length()
    );
    controlCharacteristic->notify();
    delay(40);  // small gap so Android 16 doesn’t get flooded
  }
};

// ---------------------- Setup ----------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  logLine("Boot");

  // Servo init
  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);
  servo1.write(0);
  servo2.write(0);
  logLine("Servos attached. S1 pin=" + String(SERVO1_PIN) +
          ", S2 pin=" + String(SERVO2_PIN));

  // BLE init
  BLEDevice::init(SERVER_NAME);
  // Match Flutter side MTU request (helps big notifications on newer Android)
  BLEDevice::setMTU(517);
  logLine("BLE init. Name=" + String(SERVER_NAME));

  // Server + callbacks
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  logLine("BLE server created");

  // Service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  logLine("Service created UUID=" + String(SERVICE_UUID));

  // Single characteristic for both RX (write) and TX (notify)
  controlCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  logLine("Characteristic created UUID=" + String(CHARACTERISTIC_UUID));

  controlCharacteristic->setCallbacks(new ControlCallbacks());

  // CCCD descriptor for notifications (required for many Android stacks)
  controlCharacteristic->addDescriptor(new BLE2902());

  // Start GATT + advertising
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->start();

  logLine("Advertising started");
  logLine("ESP32 BLE Ready");
}

// ---------------------- Loop ----------------------
void loop() {
  // No periodic work needed; all action via BLE callbacks.
}