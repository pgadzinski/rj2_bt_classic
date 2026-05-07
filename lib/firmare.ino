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

BLECharacteristic *pCharacteristic;

class MyCallbacks : public BLECharacteristicCallbacks {

  void onWrite(BLECharacteristic *pCharacteristic) {

   String cmd = pCharacteristic->getValue();

if (cmd.length() > 0) {

  cmd.trim();

  Serial.print("Received CMD: ");
  Serial.println(cmd);

  processCommand(cmd);
}
  }

  void processCommand(String cmd) {

    if (cmd.startsWith("S1:")) {

      int angle = constrain(cmd.substring(3).toInt(), 0, 180);

      servo1.write(angle);

      String response = "S1 -> " + String(angle) + " deg";

      Serial.println(response);

    }
    else if (cmd.startsWith("S2:")) {

      int angle = constrain(cmd.substring(3).toInt(), 0, 180);

      servo2.write(angle);

      String response = "S2 -> " + String(angle) + " deg";

      Serial.println(response);
    }
    else {

      Serial.print("Unknown Command: ");
      Serial.println(cmd);
    }
  }
};

void setup() {

  Serial.begin(115200);

  servo1.attach(SERVO1_PIN);
  servo2.attach(SERVO2_PIN);

  servo1.write(0);
  servo2.write(0);

  BLEDevice::init("RJ2_BLE");

  BLEServer *pServer = BLEDevice::createServer();

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  pCharacteristic->setCallbacks(new MyCallbacks());

  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  pAdvertising->start();

  Serial.println("ESP32 BLE Ready");
}

void loop() {

}
