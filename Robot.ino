#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

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

int speedValue = 200;  // 0 → 255

// ================== BLE & WiFi Variables ==================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

String wifi_ssid = "";
String wifi_pass = "";
bool credentialsReceived = false;

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
          Serial.println("Invalid format. Please send as: SSID,PASSWORD");
        }
      }
    }
};

void setupBLE() {
  BLEDevice::init("Robot_BLE");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
                                         CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_WRITE
                                       );

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
  pinMode(IN1_1, OUTPUT);
  pinMode(IN2_1, OUTPUT);
  pinMode(IN3_1, OUTPUT);
  pinMode(IN4_1, OUTPUT);

  pinMode(IN1_2, OUTPUT);
  pinMode(IN2_2, OUTPUT);
  pinMode(IN3_2, OUTPUT);
  pinMode(IN4_2, OUTPUT);

  // إعداد PWM
  ledcAttach(ENA1, 1000, 8);
  ledcAttach(ENB1, 1000, 8);
  ledcAttach(ENA2, 1000, 8);
  ledcAttach(ENB2, 1000, 8);

  // تشغيل البلوتوث والانتظار حتى الاتصال بالواي فاي
  setupBLE();

  while (WiFi.status() != WL_CONNECTED) {
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
        
        // إيقاف البلوتوث لتوفير الذاكرة (اختياري)
        BLEDevice::deinit(true);
        break;
      } else {
        Serial.println("\nFailed to connect to WiFi. Please check credentials and resend via BLE.");
      }
    }
    delay(100);
  }
  
  Serial.println("Robot is ready to move!");
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

// ================== LOOP TEST ==================

void loop() {

  // سرعة 128 زي المطلوبة
  setSpeed(128);   

  // يمشى لقدام لمدة ثانية ونص
  moveForward();
  delay(1500);

  // يرجع لورا لمدة ثانية ونص
  moveBackward();
  delay(1500);

  setSpeed(255);
  // يلف 360 درجة 
  turnRight();
  // السطر اللي جاي ده الوقت التقريبي للدوران، ممكن تحتاجه تقلله أو تزوده عشان يظبط لفة كاملة 360 درجة بالضبط
  delay(2000); 

  // يقف خالص
  stopMotors();

  // ميرجعش يكرر
  while(true);  
}