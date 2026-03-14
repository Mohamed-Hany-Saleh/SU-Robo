import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'dart:math';
import 'firmware_update_page.dart';

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
  bool _isBuzzerOn = false;
  double _currentSpeedGear = 3; // 1 to 4
  
  String _lastJoystickCommand = 'S';
  int _selectedIndex = 0;
  
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  
  // Voice & TTS Variables
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';

  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  final String _serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String _characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _initSpeechAndTts();
    _requestPermissions().then((_) => _startScan());
  }

  void _initSpeechAndTts() async {
    _speechEnabled = await _speechToText.initialize();
    
    // Set up TTS
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true); // Wait for speech to finish before moving to next line
    
    if (mounted) setState(() {});
  }

  void _startListening() async {
    if (await Permission.microphone.request().isGranted) {
      String? selectedLocale;
      try {
        var locales = await _speechToText.locales();
        for (var loc in locales) {
          if (loc.localeId.toLowerCase().startsWith('ar')) {
            selectedLocale = loc.localeId;
            break; // Stop at the first Arabic locale found
          }
        }
      } catch (e) {
        debugPrint("Error fetching locales: $e");
      }
      
      await _speechToText.listen(onResult: _onSpeechResult, localeId: selectedLocale);
      setState(() { _isListening = true; });
    } else {
      _showSnackBar("Microphone permission denied", isError: true);
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() { _isListening = false; });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
    });
    
    if (result.finalResult) {
       _stopListening();
       _processVoiceCommand(_lastWords.toLowerCase());
    }
  }

  Future<void> _processVoiceCommand(String command) async {
    if (_connectedDevice == null) {
      _showSnackBar("Connect to robot first before voice parsing!", isError: true);
      return;
    }
    if (_isForceStopped) {
      _showSnackBar("Force Stop is Active! Disabled voice.", isError: true);
      return;
    }
    
    String cmd = '';
    
    // Arabic + English + Phonetic parsing
    if (command.contains('قدام') || command.contains('أمام') || command.contains('forward') || command.contains('oddam') || command.contains('adam')) {
      cmd = 'F';
    } else if (command.contains('ورا') || command.contains('خلف') || command.contains('back') || command.contains('backward') || command.contains('wara')) {
      cmd = 'B';
    } else if (command.contains('يمين') || command.contains('right') || command.contains('yameen') || command.contains('you mean')) {
      cmd = 'R';
    } else if (command.contains('شمال') || command.contains('يسار') || command.contains('left') || command.contains('yasar') || command.contains('shamal')) {
      cmd = 'L';
    } else if (command.contains('لف') || command.contains('دوران') || command.contains('spin') || command.contains('javaron') || command.contains('davaron') || command.contains('dawaran')) {
      cmd = 'C';
    } else if (command.contains('قف') || command.contains('توقف') || command.contains('stop') || command.contains('qif') || command.contains('ouaf')) {
      cmd = 'S';
    } else {
      _showSnackBar('Unrecognized voice command: $command');
      return;
    }

    if (cmd == 'S') {
      _sendCommand('S');
      await _flutterTts.speak("Okay Sir, Stopping");
      return;
    }

    // TTS feedback
    _showSnackBar("Voice Command accepted: $cmd");
    await _flutterTts.speak("Okay Sir");
    
    // Command sequence (3-second auto-stop)
    _sendCommand(cmd);
    await Future.delayed(const Duration(seconds: 3));
    _sendCommand('S');
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
      
      // Request larger MTU for long OTA URLs
      await device.requestMtu(512);

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
        if (mounted) {
          setState(() {
            _selectedIndex = 3;
          });
        }
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

  String _getCommandFromJoystick(double x, double y) {
    double magnitude = sqrt(x * x + y * y);
    if (magnitude < 0.3) {
      return 'S';
    }
    double angle = atan2(y, x); // -pi to pi
    if (angle < 0) angle += 2 * pi;
    
    // Divide into 8 sectors of 45 degrees
    int sector = ((angle + pi / 8) / (pi / 4)).floor() % 8;
    switch (sector) {
      case 0: return 'R'; // Right
      case 1: return 'J'; // Backward Right
      case 2: return 'B'; // Backward
      case 3: return 'H'; // Backward Left
      case 4: return 'L'; // Left
      case 5: return 'G'; // Forward Left
      case 6: return 'F'; // Forward
      case 7: return 'I'; // Forward Right
    }
    return 'S';
  }

  void _onJoystickChanged(StickDragDetails details) {
    if (_isForceStopped) return;
    String cmd = _getCommandFromJoystick(details.x, details.y);
    if (cmd != _lastJoystickCommand) {
      _lastJoystickCommand = cmd;
      _sendCommand(cmd);
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
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomePage(),
            _buildScannerView(),
            _buildWifiPage(),
            _buildControlPage(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF15171C),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey.shade600,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Connect'),
          BottomNavigationBarItem(icon: Icon(Icons.wifi), label: 'Wi-Fi'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: 'Control'),
        ],
      ),
      floatingActionButton: _connectedDevice != null && _selectedIndex == 3 ? FloatingActionButton(
        onPressed: () {
          if (!_speechEnabled) {
            _showSnackBar("Speech integration not initialized.", isError: true);
            return;
          }
          _isListening ? _stopListening() : _startListening();
        },
        tooltip: 'Voice Command',
        backgroundColor: _isListening ? Colors.redAccent : Theme.of(context).colorScheme.primary,
        child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 28),
      ) : null,
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

  Widget _buildHomePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy, size: 100, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          const Text('Welcome to', style: TextStyle(fontSize: 20, color: Colors.grey)),
          const Text('SU Robo Controller', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          if (_connectedDevice == null)
            ElevatedButton.icon(
              onPressed: () => _onItemTapped(1),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Connect Robot'),
              style: ElevatedButton.styleFrom(
                 backgroundColor: Theme.of(context).colorScheme.primary,
                 foregroundColor: Colors.black,
                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            )
          else
            Column(
              children: [
                const Text('Status: Connected', style: TextStyle(color: Colors.tealAccent, fontSize: 18)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _onItemTapped(3),
                  icon: const Icon(Icons.gamepad),
                  label: const Text('Start Driving'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),
                // Software Update Button
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FirmwareUpdatePage(
                          characteristic: _targetCharacteristic,
                          device: _connectedDevice,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 250,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.tealAccent.shade400, Colors.blueAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.tealAccent.withValues(alpha: 0.3),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.system_update_alt, color: Colors.black, size: 24),
                        SizedBox(width: 10),
                        Text(
                          'SOFTWARE UPDATE',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotConnectedWarning() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_off, size: 80, color: Colors.grey.shade700),
          const SizedBox(height: 20),
          const Text('Robot not connected', style: TextStyle(fontSize: 24, color: Colors.grey)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _onItemTapped(1),
            style: ElevatedButton.styleFrom(
               backgroundColor: Theme.of(context).colorScheme.primary,
               foregroundColor: Colors.black,
            ),
            child: const Text('Go to Connect Tab'),
          )
        ],
      )
    );
  }

  Widget _buildWifiPage() {
    if (_connectedDevice == null) return _buildNotConnectedWarning();

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
                
                const SizedBox(height: 30),
                const Text('Wi-Fi Configuration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _ssidController,
                  decoration: const InputDecoration(labelText: 'SSID', prefixIcon: Icon(Icons.wifi)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _sendCredentials,
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.black),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('TRANSMIT TO ROBOT', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }

  Widget _buildControlPage() {
    if (_connectedDevice == null) return _buildNotConnectedWarning();

    return Container(
            color: const Color(0xFF15171C), // Slightly different shade to differentiate control pad
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const Text('Robot Live Control', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // JoyStick Area
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Joystick(
                          mode: JoystickMode.all,
                          listener: _onJoystickChanged,
                          stick: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: const Icon(Icons.gamepad, color: Colors.black, size: 30),
                          ),
                          base: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2D35),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade800, width: 3),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Speed Slider Area
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed, color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 150,
                            child: RotatedBox(
                              quarterTurns: 3, // Make slider vertical
                              child: Slider(
                                value: _currentSpeedGear,
                                min: 1,
                                max: 4,
                                divisions: 3,
                                activeColor: Theme.of(context).colorScheme.primary,
                                inactiveColor: Colors.grey.shade800,
                                onChanged: (val) {
                                  setState(() { _currentSpeedGear = val; });
                                },
                                onChangeEnd: (val) {
                                  _sendCommand(val.toInt().toString());
                                },
                              ),
                            ),
                          ),
                          Text('Gear ${_currentSpeedGear.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(Icons.rotate_right, 'C', isAction: true),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() { _isBuzzerOn = !_isBuzzerOn; });
                        _sendCommand(_isBuzzerOn ? 'Z' : 'z');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isBuzzerOn ? Colors.amber.shade700 : const Color(0xFF2A2D35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        side: BorderSide(color: _isBuzzerOn ? Colors.amber : Colors.grey.shade700),
                      ),
                      icon: Icon(_isBuzzerOn ? Icons.volume_up : Icons.volume_off),
                      label: Text(_isBuzzerOn ? 'BUZZ ON' : 'BUZZ OFF'),
                    ),
                    ElevatedButton(
                      onPressed: () => _sendCommand('S'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Icon(Icons.stop_circle, size: 30),
                    ),
                  ],
                ),
                
                // Force Stop Area
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() { _isForceStopped = !_isForceStopped; });
                        _sendCommand(_isForceStopped ? 'X' : 'Y');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isForceStopped ? Colors.redAccent.shade700 : const Color(0xFF2A2D35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        side: BorderSide(color: _isForceStopped ? Colors.redAccent : Colors.grey.shade700),
                      ),
                      icon: Icon(_isForceStopped ? Icons.lock : Icons.lock_open),
                      label: Text(_isForceStopped ? 'LOCKED' : 'FORCE STOP'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
