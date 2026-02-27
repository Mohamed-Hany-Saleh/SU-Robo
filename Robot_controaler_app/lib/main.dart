import 'dart:async';
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
      title: 'SU Robo Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Colors.tealAccent.shade400,
          secondary: Colors.blueAccent,
          surface: const Color(0xFF1E2128),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E2128),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 4,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2D35),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.tealAccent.shade400, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
      home: const BluetoothScannerScreen(),
    );
  }
}

class BluetoothScannerScreen extends StatefulWidget {
  const BluetoothScannerScreen({super.key});

  @override
  State<BluetoothScannerScreen> createState() => _BluetoothScannerScreenState();
}

class _BluetoothScannerScreenState extends State<BluetoothScannerScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPasswordVisible = false;
  bool _isForceStopped = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  final String _serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String _characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) => _startScan());
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) allGranted = false;
    });

    if (!allGranted) {
      _showSnackBar('Permissions missing. The app cannot scan for Bluetooth.', isError: true);
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    
    // Check if Bluetooth is ON before scanning
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _showSnackBar('Bluetooth is turned off! Please enable it.', isError: true);
      return;
    }

    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    
    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() {
          _isScanning = state;
        });
      }
    });

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Do not filter out empty names to ensure we actually see all raw devices during testing
          _scanResults = results.toList();
          _scanResults.sort((a, b) {
            final nameA = a.device.platformName.isNotEmpty ? a.device.platformName : a.device.advName;
            if (nameA == 'Robot_BLE') return -1;
            return b.rssi.compareTo(a.rssi); // Sort by signal strength
          });
        });
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      _showSnackBar('Error starting scan: $e', isError: true);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    
    setState(() {
      _isConnecting = true;
    });

    try {
      await device.connect(license: License.free, autoConnect: false);
      setState(() {
        _connectedDevice = device;
      });

      List<BluetoothService> services = await device.discoverServices();
      bool serviceFound = false;
      
      for (BluetoothService service in services) {
        if (service.uuid.toString() == _serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == _characteristicUuid) {
              _targetCharacteristic = characteristic;
              serviceFound = true;
              break;
            }
          }
        }
      }
      
      if (!serviceFound) {
        _showSnackBar('ESP32 Required BLE service not found.', isError: true);
        await device.disconnect();
        setState(() {
          _connectedDevice = null;
        });
      } else {
        _showSnackBar('Connected securely to ${device.platformName.isNotEmpty ? device.platformName : device.advName}');
      }
      
    } catch (e) {
      _showSnackBar('Connection failed: $e', isError: true);
      setState(() {
        _connectedDevice = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
        _targetCharacteristic = null;
      });
      _showSnackBar('Disconnected');
      _startScan();
    }
  }

  Future<void> _sendCredentials() async {
    if (_targetCharacteristic == null || _connectedDevice == null) {
      _showSnackBar('Not connected to a valid device!', isError: true);
      return;
    }

    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      _showSnackBar('Please enter Wi-Fi SSID', isError: true);
      return;
    }

    final payload = '$ssid,$password';
    
    try {
      await _targetCharacteristic!.write(utf8.encode(payload), withoutResponse: false);
      _showSnackBar('Wi-Fi Credentials sent to Robot successfully!');
    } catch (e) {
      _showSnackBar('Failed to send payload: $e', isError: true);
    }
  }

  Future<void> _sendCommand(String cmd) async {
    if (_targetCharacteristic == null || _connectedDevice == null) {
      _showSnackBar('Not connected to a valid device!', isError: true);
      return;
    }
    try {
      await _targetCharacteristic!.write(utf8.encode(cmd), withoutResponse: false);
      if (cmd == 'D') {
        _showSnackBar('Wi-Fi Disconnect command sent to Robot.');
      }
    } catch (e) {
      _showSnackBar('Failed to send command: $e', isError: true);
    }
  }

  Widget _buildControlButton(IconData icon, String cmd, {bool isAction = false}) {
    final isDisabled = _isForceStopped;
    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => _sendCommand(cmd),
      onTapUp: isDisabled ? null : (isAction ? null : (_) => _sendCommand('S')),
      onTapCancel: isDisabled ? null : (isAction ? null : () => _sendCommand('S')),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: isDisabled 
                 ? Colors.grey.shade900 
                 : (isAction ? Colors.purpleAccent.withValues(alpha: 0.2) : const Color(0xFF2A2D35)),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDisabled 
                   ? Colors.grey.shade800 
                   : (isAction ? Colors.purpleAccent : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            width: 2,
          ),
          boxShadow: isDisabled ? [] : [
            BoxShadow(
              color: isAction ? Colors.purpleAccent.withValues(alpha: 0.2) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ]
        ),
        child: Icon(icon, size: 36, color: isDisabled ? Colors.grey.shade700 : (isAction ? Colors.purpleAccent : Theme.of(context).colorScheme.primary)),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.redAccent.shade700 : Colors.teal.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _connectedDevice?.disconnect();
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
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Center(
                child: SizedBox(
                  width: 20, 
                  height: 20, 
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)
                )
              ),
            ),
          if (!_isScanning && _connectedDevice == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Scan for Devices',
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _connectedDevice == null ? _buildScannerView() : _buildControlView(),
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
               Icon(Icons.bluetooth_searching, color: Theme.of(context).colorScheme.primary, size: 28),
               const SizedBox(width: 12),
               const Text(
                 'Available Devices',
                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
               ),
            ],
          ),
        ),
        Expanded(
          child: _scanResults.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_disabled, size: 60, color: Colors.grey.shade700),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning ? 'Searching for robots...' : 'No devices found.\nMake sure location and bluetooth are on.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _startScan,
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final name = result.device.platformName.isNotEmpty 
                                  ? result.device.platformName 
                                  : (result.device.advName.isNotEmpty ? result.device.advName : 'Unknown Device');
                      
                      final isTarget = name == 'Robot_BLE';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: isTarget ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5) : BorderSide.none,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: isTarget ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Colors.grey.shade800,
                            child: Icon(
                              isTarget ? Icons.smart_toy : Icons.bluetooth,
                              color: isTarget ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                            ),
                          ),
                          title: Text(name, style: TextStyle(fontWeight: isTarget ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(result.device.remoteId.str),
                          trailing: _isConnecting
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    backgroundColor: isTarget ? Theme.of(context).colorScheme.primary : const Color(0xFF2A2D35),
                                    foregroundColor: isTarget ? Colors.black : Colors.white,
                                  ),
                                  onPressed: () => _connectToDevice(result.device),
                                  child: const Text('Connect'),
                                ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildControlView() {
    final name = _connectedDevice!.platformName.isNotEmpty 
                 ? _connectedDevice!.platformName 
                 : (_connectedDevice!.advName.isNotEmpty ? _connectedDevice!.advName : 'Robot');
                 
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                   Colors.tealAccent.shade400.withValues(alpha: 0.2),
                   Colors.blueAccent.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.shade400.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle, color: Colors.tealAccent.shade400, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connected to', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                      Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white70),
                  onPressed: _disconnect,
                  tooltip: 'Disconnect',
                )
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          const Text(
            'Wi-Fi Configuration',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter network details to connect the robot to the internet.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          
          const SizedBox(height: 30),
          
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi Network Name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          
          const SizedBox(height: 20),
          
          TextField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            decoration: InputDecoration(
              labelText: 'Wi-Fi Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
            ),
          ),
          
          const SizedBox(height: 40),
          
          ElevatedButton(
            onPressed: _sendCredentials,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.send_rounded),
                SizedBox(width: 12),
                Text('TRANSMIT TO ROBOT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          const Divider(color: Colors.white24, thickness: 1),
          const SizedBox(height: 20),
          const Text(
            'Robot Live Control',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Press and hold a button to move. Release to stop.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(Icons.keyboard_arrow_up, 'F'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(Icons.keyboard_arrow_left, 'L'),
              const SizedBox(width: 16),
              _buildControlButton(Icons.rotate_right, 'C', isAction: true),
              const SizedBox(width: 16),
              _buildControlButton(Icons.keyboard_arrow_right, 'R'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(Icons.keyboard_arrow_down, 'B'),
            ],
          ),
          
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _sendCommand('S'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                icon: const Icon(Icons.stop_circle, size: 26),
                label: const Text('STOP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isForceStopped = !_isForceStopped;
                  });
                  _sendCommand(_isForceStopped ? 'X' : 'Y');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isForceStopped ? Colors.redAccent.shade700 : const Color(0xFF2A2D35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  side: BorderSide(
                    color: _isForceStopped ? Colors.redAccent : Colors.grey.shade700,
                    width: 2,
                  ),
                ),
                icon: Icon(_isForceStopped ? Icons.lock : Icons.lock_open, size: 26),
                label: Text(_isForceStopped ? 'LOCKED' : 'FORCE STOP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () => _sendCommand('D'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.wifi_off),
            label: const Text('DISCONNECT WI-FI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
