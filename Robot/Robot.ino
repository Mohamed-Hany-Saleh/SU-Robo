#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <HTTPUpdate.h>
#include <WiFiClientSecure.h>

void moveForward();
void moveBackward();
void stopMotors();
void turnRight();
void turnLeft();
void moveForwardRight();
void moveForwardLeft();
void moveBackwardRight();
void moveBackwardLeft();
void setSpeed(int spd);
void performOTA(String url);

// ================== Driver 1 (Rear) ==================
#define ENA1 26
#define IN1_1 25
#define IN2_1 33
#define ENB1 27
#define IN3_1 32
#define IN4_1 14

// ================== Driver 2 (Front) ==================
#define ENA2 19
#define IN1_2 18
#define IN2_2 5
#define ENB2 4
#define IN3_2 17
#define IN4_2 16

// ================== Buzzer ==================
#define BUZZER_PIN 21

// ================== Line Follower Sensors ==================
#define SENSOR_LEFT 13
#define SENSOR_CENTER 34
#define SENSOR_RIGHT 35

// (1 = Black Line, 0 = White/No Line) 
// The sensor gives HIGH when on a Black Line (absorbing) and LOW on a White surface (reflecting)
#define BLACK_LINE HIGH

int speedValue = 200;  // 0 → 255

// ================== BLE & WiFi Variables ==================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

String wifi_ssid = "";
String wifi_pass = "";
bool credentialsReceived = false;

BLECharacteristic *pGlobalCharacteristic;

bool isSpinning = false;
unsigned long spinStartTime = 0;
bool isForceStopped = false;
bool isLineFollowerMode = false;

// OTA Pending Flags
bool pendingOTA = false;
String pendingOTAUrl = "";

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue().c_str();
      if (value.length() > 0) {
        // ننتظر أن يقوم المستخدم بإرسال اسم الشبكة والباسورد مفصولين بفاصلة، هكذا: SSID,PASSWORD
        int separatorIndex = value.indexOf(',');
        if (separatorIndex > 0) {
          wifi_ssid = value.substring(0, separatorIndex);
          wifi_pass = value.substring(separatorIndex + 1);
          wifi_ssid.trim();
          wifi_pass.trim();
          credentialsReceived = true;
          Serial.println("=================================");
          Serial.println("Credentials Received via BLE:");
          Serial.print("SSID: "); Serial.println(wifi_ssid);
          Serial.print("PASS: "); Serial.println(wifi_pass);
          Serial.println("=================================");
        } else {
          value.trim();
          Serial.print("Command Received: ");
          Serial.println(value);
          
          if (value.startsWith("OTA:")) {
            pendingOTAUrl = value.substring(4);
            pendingOTAUrl.trim();
            pendingOTA = true;
            Serial.println("OTA Update Queued...");
          }
          else if (value == "X") {
            Serial.println("Force Stop Enabled!");
            isForceStopped = true;
            isSpinning = false;
            isLineFollowerMode = false;
            stopMotors();
          }
          else if (value == "Y") {
            Serial.println("Force Stop Disabled.");
            isForceStopped = false;
          }
          else if (value == "MODE:LINE") {
            isLineFollowerMode = true;
            isSpinning = false;
            Serial.println("Mode: Line Follower Active");
          }
          else if (value == "MODE:MANUAL") {
            isLineFollowerMode = false;
            stopMotors();
            Serial.println("Mode: Manual Control");
          }
          else if (value == "S") {
            isSpinning = false;
            stopMotors();
          }
          else if (value == "Z") {
            digitalWrite(BUZZER_PIN, HIGH);
            Serial.println("Buzzer ON");
          }
          else if (value == "z") {
            digitalWrite(BUZZER_PIN, LOW);
            Serial.println("Buzzer OFF");
          }
          else if (value == "D") {
            WiFi.disconnect();
            Serial.println("WiFi Disconnected via BLE Command.");
          }
          else if (value == "W?") {
            if (WiFi.status() == WL_CONNECTED) {
              pCharacteristic->setValue("W:1");
            } else {
              pCharacteristic->setValue("W:0");
            }
            pCharacteristic->notify();
            Serial.println("WiFi Status Requested and Sent.");
          }
          else if (value == "1") { setSpeed(80);  Serial.println("Speed -> Gear 1"); }
          else if (value == "2") { setSpeed(140); Serial.println("Speed -> Gear 2"); }
          else if (value == "3") { setSpeed(200); Serial.println("Speed -> Gear 3"); }
          else if (value == "4") { setSpeed(255); Serial.println("Speed -> Gear 4"); }
          else if (!isForceStopped) {
            if (value == "F") { isSpinning = false; moveForward(); }
            else if (value == "B") { isSpinning = false; moveBackward(); }
            else if (value == "R") { isSpinning = false; turnRight(); }
            else if (value == "L") { isSpinning = false; turnLeft(); }
            else if (value == "I") { isSpinning = false; moveForwardRight(); }
            else if (value == "G") { isSpinning = false; moveForwardLeft(); }
            else if (value == "J") { isSpinning = false; moveBackwardRight(); }
            else if (value == "H") { isSpinning = false; moveBackwardLeft(); }
            else if (value == "C") {
              Serial.println("Starting 360 Spin...");
              setSpeed(255);
              turnRight();
              isSpinning = true;
              spinStartTime = millis();
            }
            else {
              Serial.println("Unknown command or format.");
            }
          }
          else {
            Serial.println("Command ignored: Force stop is active.");
          }
        }
      }
    }
};

void performOTA(String url) {
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Preparing for OTA. Deinitializing BLE to free memory...");
    
    // Send one last notification if possible
    if (pGlobalCharacteristic) {
      pGlobalCharacteristic->setValue("OTA:START");
      pGlobalCharacteristic->notify();
      delay(500);
    }
    
    // Deinit BLE to save ~100KB of heap
    BLEDevice::deinit(true);
    delay(1000);
    
    Serial.print("Free heap before OTA: ");
    Serial.println(ESP.getFreeHeap());

    WiFiClientSecure client;
    client.setInsecure(); 
    client.setHandshakeTimeout(60); 
    
    httpUpdate.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
    httpUpdate.rebootOnUpdate(false);
    
    Serial.println("Starting OTA from: " + url);
    t_httpUpdate_return ret = httpUpdate.update(client, url);
    
    switch (ret) {
      case HTTP_UPDATE_FAILED:
        Serial.printf("HTTP_UPDATE_FAILED Error (%d): %s\n", httpUpdate.getLastError(), httpUpdate.getLastErrorString().c_str());
        if (httpUpdate.getLastError() == 10) {
          Serial.println("CRITICAL: Partition scheme does NOT support OTA!");
          Serial.println("Please change IDE Partition Scheme to: 'Minimal SPIFFS (1.9MB APP with OTA)'");
        }
        Serial.println("OTA Failed. Restarting robot in 5 seconds to recover...");
        delay(5000);
        ESP.restart(); // safer than re-initializing BLE after deinit
        break;
      case HTTP_UPDATE_NO_UPDATES:
        Serial.println("HTTP_UPDATE_NO_UPDATES. Restarting...");
        delay(2000);
        ESP.restart();
        break;
      case HTTP_UPDATE_OK:
        Serial.println("HTTP_UPDATE_OK. Update successful!");
        Serial.println("Restarting robot in 3 seconds...");
        delay(3000);
        ESP.restart();
        break;
    }
  } else {
    Serial.println("Cannot perform OTA: WiFi not connected");
  }
}

void setupBLE() {
  BLEDevice::init("Robot_BLE");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
                                         CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_WRITE | 
                                         BLECharacteristic::PROPERTY_NOTIFY
                                       );

  pCharacteristic->addDescriptor(new BLE2902());
  pGlobalCharacteristic = pCharacteristic;

  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("BLE Started!");
  Serial.println("Please connect to Bluetooth device named 'Robot_BLE'");
  Serial.println("Send Wi-Fi info formatted as: SSID,PASSWORD");
  Serial.println("Waiting for credentials...");
}

void setup() {
  Serial.begin(115200);

  // اتجاه البنات
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(IN1_1, OUTPUT);
  pinMode(IN2_1, OUTPUT);
  pinMode(IN3_1, OUTPUT);
  pinMode(IN4_1, OUTPUT);

  pinMode(IN1_2, OUTPUT);
  pinMode(IN2_2, OUTPUT);
  pinMode(IN3_2, OUTPUT);
  pinMode(IN4_2, OUTPUT);

  // Line Follower
  pinMode(SENSOR_LEFT, INPUT);
  pinMode(SENSOR_CENTER, INPUT);
  pinMode(SENSOR_RIGHT, INPUT);

  // إعداد PWM
  ledcAttach(ENA1, 1000, 8);
  ledcAttach(ENB1, 1000, 8);
  ledcAttach(ENA2, 1000, 8);
  ledcAttach(ENB2, 1000, 8);

  // Boot Beep to indicate new firmware is running
  for(int i=0; i<3; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(100);
    digitalWrite(BUZZER_PIN, LOW);
    delay(100);
  }

  // تشغيل البلوتوث
  setupBLE();
  
  Serial.println("Robot is ready to move! Main loop is free.");
}

// ================== MOVEMENT ==================

void moveForward() {

  // خلفي
  digitalWrite(IN1_1, HIGH);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN3_1, HIGH);
  digitalWrite(IN4_1, LOW);

  // أمامي
  digitalWrite(IN1_2, HIGH);
  digitalWrite(IN2_2, LOW);
  digitalWrite(IN3_2, HIGH);
  digitalWrite(IN4_2, LOW);

  setSpeed(speedValue);
}

void moveBackward() {

  // خلفي
  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, HIGH);
  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, HIGH);

  // أمامي
  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, HIGH);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, HIGH);

  setSpeed(speedValue);
}

void stopMotors() {

  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, LOW);

  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, LOW);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, LOW);

  ledcWrite(ENA1, 0);
  ledcWrite(ENB1, 0);
  ledcWrite(ENA2, 0);
  ledcWrite(ENB2, 0);
}

void setSpeed(int spd) {
  speedValue = spd;
  ledcWrite(ENA1, spd);
  ledcWrite(ENB1, spd);
  ledcWrite(ENA2, spd);
  ledcWrite(ENB2, spd);
}

void turnRight() {
  // عجل شمال (يسار) لقدام
  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, HIGH);
  digitalWrite(IN1_2, HIGH);
  digitalWrite(IN2_2, LOW);

  // عجل يمين لورا
  digitalWrite(IN3_1, HIGH);
  digitalWrite(IN4_1, LOW);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, HIGH);
  
  setSpeed(speedValue);
}

void turnLeft() {
  // عكس حركة turnRight تقريباً للانعطاف لليسار
  digitalWrite(IN1_1, HIGH);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, HIGH);

  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, HIGH);
  digitalWrite(IN3_2, HIGH);
  digitalWrite(IN4_2, LOW);
  
  setSpeed(speedValue);
}

void moveForwardRight() {
  // للتحرك يمين للأمام بزاوية (تشغيل العجل الشمال للأمام وإيقاف اليمين)
  digitalWrite(IN1_1, HIGH);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN1_2, HIGH);
  digitalWrite(IN2_2, LOW);

  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, LOW);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, LOW);
  
  setSpeed(speedValue);
}

void moveForwardLeft() {
  // للتحرك يسار للأمام بزاوية (إيقاف العجل الشمال وتشغيل اليمين للأمام)
  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, LOW);

  digitalWrite(IN3_1, HIGH);
  digitalWrite(IN4_1, LOW);
  digitalWrite(IN3_2, HIGH);
  digitalWrite(IN4_2, LOW);
  
  setSpeed(speedValue);
}

void moveBackwardRight() {
  // للتحرك يمين للخلف بزاوية (تشغيل العجل الشمال للخلف وإيقاف اليمين)
  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, HIGH);
  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, HIGH);

  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, LOW);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, LOW);
  
  setSpeed(speedValue);
}

void moveBackwardLeft() {
  // للتحرك يسار للخلف بزاوية (إيقاف العجل الشمال وتشغيل اليمين للخلف)
  digitalWrite(IN1_1, LOW);
  digitalWrite(IN2_1, LOW);
  digitalWrite(IN1_2, LOW);
  digitalWrite(IN2_2, LOW);

  digitalWrite(IN3_1, LOW);
  digitalWrite(IN4_1, HIGH);
  digitalWrite(IN3_2, LOW);
  digitalWrite(IN4_2, HIGH);
  
  setSpeed(speedValue);
}

// ================== LOOP TEST ==================

void loop() {
  if (credentialsReceived) {
    credentialsReceived = false;
    Serial.print("Connecting to WiFi: ");
    Serial.println(wifi_ssid);
    
    WiFi.begin(wifi_ssid.c_str(), wifi_pass.c_str());

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      Serial.print(".");
      attempts++;
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWiFi Connected successfully!");
      Serial.print("IP Address: ");
      Serial.println(WiFi.localIP());
      // Beep indicating successful Wi-Fi link
      digitalWrite(BUZZER_PIN, HIGH); delay(200); digitalWrite(BUZZER_PIN, LOW);
    } else {
      Serial.println("\nFailed to connect to WiFi.");
    }
  }

  if (pendingOTA) {
    pendingOTA = false;
    Serial.println("Executing Queued OTA...");
    delay(500); // Give some time for BLE to stabilize
    performOTA(pendingOTAUrl);
  }

  if (isLineFollowerMode && !isForceStopped) {
    int leftS = digitalRead(SENSOR_LEFT);
    int centerS = digitalRead(SENSOR_CENTER);
    int rightS = digitalRead(SENSOR_RIGHT);

    static int lastAction = -1;
    int targetAction = 0; // 0=Stop, 1=Forward, 2=Left, 3=Right

    // Line Follower Algorithm
    if (centerS == BLACK_LINE && leftS != BLACK_LINE && rightS != BLACK_LINE) {
      targetAction = 1; // Forward
    } 
    else if (leftS == BLACK_LINE && centerS != BLACK_LINE) {
      targetAction = 2; // Turn Left
    } 
    else if (rightS == BLACK_LINE && centerS != BLACK_LINE) {
      targetAction = 3; // Turn Right
    } 
    else if (leftS != BLACK_LINE && centerS != BLACK_LINE && rightS != BLACK_LINE) {
      targetAction = 0; // Stop (Lost line)
    }
    else {
      targetAction = 1; // Multiple sensors triggered, edge case -> Forward
    }

    if (targetAction != lastAction) {
      if (targetAction != 0) {
        digitalWrite(BUZZER_PIN, HIGH); // Quick beep when starting a movement
      }

      if (targetAction == 1) moveForward();
      else if (targetAction == 2) turnLeft();
      else if (targetAction == 3) turnRight();
      else stopMotors();
      
      if (targetAction != 0) {
        delay(5); // 5ms micro-click to avoid blocking the robot's movement
        digitalWrite(BUZZER_PIN, LOW);
      }
      
      lastAction = targetAction;
    }
  }

  if (isSpinning) {
    if (millis() - spinStartTime >= 2000) {
      // بعد ثانيتين يقف
      stopMotors();
      isSpinning = false;
      Serial.println("360 Spin Complete.");
    }
  } else if (!isLineFollowerMode) {
    delay(10);
  }
}