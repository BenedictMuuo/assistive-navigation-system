/*
  Wearable Distance Unit - ESP32 DevKit V1 + HC-SR04
  Project: CNN-Based Smart Assistive Navigation and Caregiver Alert System
  Author:  Benedict Muuo

  What it does:
  - Measures the distance to the object in front using the HC-SR04.
  - Puts the distance into a band: NEAR (< 100 cm), MEDIUM (100-300 cm), FAR (> 300 cm)
    These match the distance bands in the app (DistanceBander: 1 m and 3 m).
  - Blinks the on-board LED faster when the object is closer.
  - In simulation: prints the distance to the Serial Monitor.
  - On the real board: also sends the distance to the phone over Bluetooth (BLE).

  Set SIMULATION to true in Wokwi, and false when you upload to the real ESP32.
*/

#define SIMULATION true

#if !SIMULATION
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#endif

// ---------- Pins ----------
const int TRIG_PIN = 5;    // P5  -> HC-SR04 TRIG
const int ECHO_PIN = 18;   // P18 -> HC-SR04 ECHO (sensor powered from 3V3, so ECHO is 3.3V and safe)
const int LED_PIN  = 2;    // On-board blue LED

// ---------- Distance bands (cm) ----------
const float NEAR_LIMIT   = 100.0;
const float MEDIUM_LIMIT = 300.0;

// ---------- Timing ----------
const unsigned long READ_INTERVAL_MS = 250;   // about 4 readings per second
unsigned long lastRead = 0;
unsigned long lastBlink = 0;
bool ledOn = false;

float currentDistance = -1;   // -1 means "nothing in range"

#if !SIMULATION
// UUIDs the Flutter app will look for
#define SERVICE_UUID        "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

BLECharacteristic *distanceChar = nullptr;
bool phoneConnected = false;

class ConnectionCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    phoneConnected = true;
  }
  void onDisconnect(BLEServer *server) override {
    phoneConnected = false;
    BLEDevice::startAdvertising();   // let the phone reconnect
  }
};

void setupBLE() {
  BLEDevice::init("AssistNav-Wearable");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ConnectionCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);
  distanceChar = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  distanceChar->addDescriptor(new BLE2902());
  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  BLEDevice::startAdvertising();
}
#endif

// Take one reading in cm. Returns -1 if nothing is in range.
// This sensor (3.3-5V version) needs a 20 us trigger pulse and about 60 ms rest between pings.
float readOnce() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(5);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(20);
  digitalWrite(TRIG_PIN, LOW);

  long duration = pulseIn(ECHO_PIN, HIGH, 40000);   // 40 ms timeout (about 6 m)
  if (duration == 0) return -1;

  float cm = duration * 0.0343 / 2.0;
  if (cm < 2 || cm > 400) return -1;               // outside the sensor's range
  return cm;
}

// Take 3 readings, 60 ms apart, and ignore missed ones.
// If 3 are good, keep the middle one. If 1-2 are good, use them. If none, return -1.
float readDistance() {
  float good[3];
  int count = 0;

  for (int i = 0; i < 3; i++) {
    float cm = readOnce();
    if (cm > 0) good[count++] = cm;
    if (i < 2) delay(60);
  }

  if (count == 0) return -1;
  if (count == 1) return good[0];
  if (count == 2) return (good[0] + good[1]) / 2.0;

  // sort 3 values and return the middle one
  if (good[0] > good[1]) { float t = good[0]; good[0] = good[1]; good[1] = t; }
  if (good[1] > good[2]) { float t = good[1]; good[1] = good[2]; good[2] = t; }
  if (good[0] > good[1]) { float t = good[0]; good[0] = good[1]; good[1] = t; }
  return good[1];
}

const char *bandFor(float cm) {
  if (cm < 0)             return "CLEAR";
  if (cm < NEAR_LIMIT)    return "NEAR";
  if (cm < MEDIUM_LIMIT)  return "MEDIUM";
  return "FAR";
}

// Blink speed shows how close the object is.
void updateLed(float cm) {
  unsigned long interval;
  if (cm < 0 || cm >= MEDIUM_LIMIT) {
    digitalWrite(LED_PIN, LOW);
    ledOn = false;
    return;
  } else if (cm < NEAR_LIMIT) {
    interval = 100;   // fast blink
  } else {
    interval = 500;   // slow blink
  }

  if (millis() - lastBlink >= interval) {
    lastBlink = millis();
    ledOn = !ledOn;
    digitalWrite(LED_PIN, ledOn ? HIGH : LOW);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(LED_PIN, OUTPUT);

#if !SIMULATION
  setupBLE();
  Serial.println("BLE ready. Waiting for the phone...");
#else
  Serial.println("Bluetooth off (SIMULATION true). Printing distance readings...");
#endif
}

void loop() {
  if (millis() - lastRead >= READ_INTERVAL_MS) {
    lastRead = millis();
    currentDistance = readDistance();

    // Message format the phone app will read, e.g. "DIST:85;BAND:NEAR"
    char message[32];
    snprintf(message, sizeof(message), "DIST:%d;BAND:%s",
             (int)currentDistance, bandFor(currentDistance));
    Serial.println(message);

#if !SIMULATION
    if (phoneConnected) {
      distanceChar->setValue((uint8_t *)message, strlen(message));
      distanceChar->notify();
    }
#endif
  }

  updateLed(currentDistance);
}
