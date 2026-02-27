# SU Robo Controller

A Flutter application designed to connect to an ESP32 robot via Bluetooth Low Energy (BLE) and send Wi-Fi credentials effortlessly. This project runs entirely isolated within a Docker container, keeping your host machine clean.

## Prerequisites
- Docker engine installed and running.
- A physical Android device with "Wireless Debugging" enabled (or connected via USB and `adb tcpip` configured).

## How to Run the App (Dockerized)

Follow these steps to build and run the app directly on your physical phone:

1. **Start the Docker Environment**:
   Run the `up.bat` script. This will build the Ubuntu-based image with the Android and Flutter SDKs, and start the container as a background service:
   ```cmd
   .\up.bat
   ```

2. **Open the Developer Shell**:
   Enter the interactive shell inside the running container using the `shell.bat` script:
   ```cmd
   .\shell.bat
   ```

3. **Connect Your Phone via ADB**:
   While inside the shell, connect to your phone over Wi-Fi. Replace `192.168.x.x` with your phone's actual IP address:
   ```bash
   adb connect 192.168.x.x:5555
   ```
   *(If prompted on your phone, accept the debugging connection).*

4. **Run the Flutter Application**:
   Now that the device is connected, deploy the app:
   ```bash
   flutter run
   ```

## Features
- Modern, dynamic UI for scanning BLE devices.
- Auto-filters to find the specific `Robot_BLE` device.
- Input fields to transmit `SSID` and `PASSWORD` directly to the robot.
