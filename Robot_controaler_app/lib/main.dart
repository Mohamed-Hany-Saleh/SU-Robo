import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SU Robo controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const BluetoothControllerScreen(),
    );
  }
}

class BluetoothControllerScreen extends StatefulWidget {
  const BluetoothControllerScreen({super.key});

  @override
  State<BluetoothControllerScreen> createState() => _BluetoothControllerScreenState();
}

class _BluetoothControllerScreenState extends State<BluetoothControllerScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  BluetoothDevice? _espDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMessage = 'Ready to connect';

  // UUIDs matching the Arduino code
  final String _serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String _characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _scanAndConnect() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning for Robot_BLE...';
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == 'Robot_BLE' || r.device.advName == 'Robot_BLE') {
            await FlutterBluePlus.stopScan();
            setState(() {
              _isScanning = false;
              _espDevice = r.device;
              _statusMessage = 'Found Robot_BLE, connecting...';
            });
            await _connectToDevice(r.device);
            break;
          }
        }
      });
      
      // Handle timeout if device not found
      Future.delayed(const Duration(seconds: 10), () {
        if (_isScanning) {
           FlutterBluePlus.stopScan();
           setState(() {
             _isScanning = false;
             if (_espDevice == null) {
                _statusMessage = 'Robot_BLE not found. Try again.';
             }
           });
        }
      });

    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'Error starting scan: $e';
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(license: License.free, autoConnect: false);
      setState(() {
        _isConnected = true;
        _statusMessage = 'Connected to Robot_BLE.\nDiscovering services...';
      });

      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == _serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == _characteristicUuid) {
              setState(() {
                 _targetCharacteristic = characteristic;
                 _statusMessage = 'Ready to send credentials!';
              });
              return;
            }
          }
        }
      }
      
      setState(() {
         _statusMessage = 'Required BLE service not found on device.';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _statusMessage = 'Connection failed: $e';
      });
    }
  }

  Future<void> _sendCredentials() async {
    if (_targetCharacteristic == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected or characteristic not found!')),
      );
      return;
    }

    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Wi-Fi SSID')),
      );
      return;
    }

    // Format matches Arduino code: SSID,PASSWORD
    final payload = '$ssid,$password';
    
    try {
      await _targetCharacteristic!.write(utf8.encode(payload), withoutResponse: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials sent successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    }
  }

  @override
  void dispose() {
    _espDevice?.disconnect();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SU Robo Controller'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_connected, color: Colors.green),
              onPressed: () {},
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Card(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Text(
                   _statusMessage,
                   textAlign: TextAlign.center,
                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                 ),
               ),
             ),
             const SizedBox(height: 20),
             ElevatedButton.icon(
                onPressed: _isScanning || _isConnected ? null : _scanAndConnect,
                icon: _isScanning 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Scanning...' : 'Connect to ESP32'),
             ),
             const SizedBox(height: 40),
             TextField(
               controller: _ssidController,
               decoration: const InputDecoration(
                 labelText: 'Wi-Fi SSID',
                 border: OutlineInputBorder(),
                 prefixIcon: Icon(Icons.wifi),
               ),
             ),
             const SizedBox(height: 16),
             TextField(
               controller: _passwordController,
               obscureText: true,
               decoration: const InputDecoration(
                 labelText: 'Wi-Fi Password',
                 border: OutlineInputBorder(),
                 prefixIcon: Icon(Icons.lock),
               ),
             ),
             const SizedBox(height: 30),
             ElevatedButton(
               onPressed: _isConnected && _targetCharacteristic != null ? _sendCredentials : null,
               style: ElevatedButton.styleFrom(
                 padding: const EdgeInsets.symmetric(vertical: 16),
                 backgroundColor: Theme.of(context).colorScheme.primary,
                 foregroundColor: Theme.of(context).colorScheme.onPrimary,
               ),
               child: const Text('Send to Robot', style: TextStyle(fontSize: 18)),
             ),
          ],
        ),
      ),
    );
  }
}
