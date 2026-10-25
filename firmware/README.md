# ESP32 sensor unit

Wearable ultrasonic distance sensor. It measures the distance to the obstacle
ahead and sends it to the phone over Bluetooth Low Energy (BLE).

The app reads it through `BleDistanceSource`
(`app/lib/services/distance/ble_distance_source.dart`). If the sensor is
missing or the link drops, the app carries on with camera-only warnings.

## Hardware

| Part | Notes |
|------|-------|
| ESP32 development board (ESP-WROOM-32, 38-pin, CP2102, USB-C) | Pins are labelled P5, P18 and so on |
| HC-SR04 ultrasonic sensor, 3.3–5 V version | Runs from 3.3 V, so ECHO is safe for the ESP32 |
| USB power bank and USB-C cable | Powers the unit when worn |

## Wiring

| HC-SR04 | ESP32 |
|---------|-------|
| VCC | 3V3 |
| TRIG | P5 (GPIO 5) |
| ECHO | P18 (GPIO 18) |
| GND | GND |

Power the sensor from 3V3, not 5V. On this sensor, ECHO comes out at the same
voltage as VCC, and the ESP32 pins only take 3.3 V.

## Uploading

1. Arduino IDE 2, with "esp32 by Espressif Systems" from the Boards Manager.
2. Board: **ESP32 Dev Module**. Windows needs the Silicon Labs CP210x driver.
3. Open `wearable_distance/wearable_distance.ino`.
4. Set `SIMULATION` to `false` for the real board (`true` turns Bluetooth off
   and only prints to the Serial Monitor; also used in the Wokwi simulation).
5. Click Upload. On this board, hold **BOOT** while it says "Connecting...".

## What it sends

The unit advertises as **AssistNav-Wearable** and sends a text notification
about four times a second:

```
DIST:85;BAND:NEAR
```

| Field | Meaning |
|-------|---------|
| `DIST` | Distance in centimetres. `-1` means no echo, nothing in range |
| `BAND` | NEAR (< 1 m), MEDIUM (1–3 m), FAR (> 3 m), CLEAR (no reading) |

| | UUID |
|--|------|
| Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| Distance characteristic (read, notify) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |

These are the Nordic UART Service IDs, so tools such as nRF Connect label the
service "Nordic UART Service".

## Timing

This sensor needs a 20 µs trigger pulse and about 60 ms between pings. Each
reading takes three pings and keeps the middle value, ignoring missed echoes.
