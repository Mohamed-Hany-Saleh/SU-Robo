import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

class FirmwareUpdatePage extends StatefulWidget {
  final BluetoothCharacteristic? characteristic;
  final BluetoothDevice? device;

  const FirmwareUpdatePage({
    super.key,
    required this.characteristic,
    required this.device,
  });

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;

  // Release info
  String? _latestVersion;
  String? _releaseDate;
  String? _releaseNotes;
  String? _firmwareUrl;
  String? _firmwareSize;
  bool _isWifiConnected = false;
  bool _checkingWifi = true;
  StreamSubscription? _notifySubscription;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const String _repoOwner = 'Mohamed-Hany-Saleh';
  static const String _repoName = 'SU-Robo';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _checkForUpdates();
    _setupNotifications();
  }

  void _setupNotifications() async {
    if (widget.characteristic == null) return;

    try {
      await widget.characteristic!.setNotifyValue(true);
      _notifySubscription = widget.characteristic!.onValueReceived.listen((value) {
        final message = utf8.decode(value).trim();
        debugPrint('BLE Notification: $message');

        if (message == 'W:1') {
          setState(() {
            _isWifiConnected = true;
            _checkingWifi = false;
          });
        } else if (message == 'W:0') {
          setState(() {
            _isWifiConnected = false;
            _checkingWifi = false;
          });
        } else if (message == 'OTA:START') {
          _showFinalizingDialog();
        } else if (message == 'OTA:SUCCESS') {
          _showSuccessDialog();
        }
      });

      // Ask for WiFi status
      await widget.characteristic!.write(utf8.encode('W?'), withoutResponse: false);
    } catch (e) {
      debugPrint('Error setting up notifications: $e');
      setState(() => _checkingWifi = false);
    }
  }

  void _showFinalizingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2128),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.rocket_launch, color: Colors.tealAccent, size: 60),
            SizedBox(height: 16),
            Text('Update Started!', textAlign: TextAlign.center),
          ],
        ),
        content: const Text(
          'The robot has begun the update. It will temporarily disconnect and then restart with the new firmware.\n\nPlease wait 1-2 minutes then reconnect.',
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // Go back to Home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('UNDERSTOOD'),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    if (!mounted) return;
    setState(() => _isUpdating = false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2128),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.tealAccent, size: 60),
            SizedBox(height: 16),
            Text('Update Complete!', textAlign: TextAlign.center),
          ],
        ),
        content: const Text(
          'The firmware has been updated successfully. The robot is restarting and will be ready in a few seconds.',
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // Go back to Home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('GREAT!'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _notifySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final assets = data['assets'] as List<dynamic>;

        // Look for a .bin firmware file in the release assets
        String? binUrl;
        String? binSize;
        for (final asset in assets) {
          final name = asset['name'] as String;
          if (name.endsWith('.bin')) {
            binUrl = asset['browser_download_url'] as String;
            final sizeBytes = asset['size'] as int;
            binSize = _formatBytes(sizeBytes);
            break;
          }
        }

        final publishedAt = data['published_at'] as String;
        final date = DateTime.parse(publishedAt);

        setState(() {
          _latestVersion = data['tag_name'] as String? ?? 'Unknown';
          _releaseDate =
              '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          _releaseNotes = data['body'] as String? ?? 'No release notes.';
          _firmwareUrl = binUrl;
          _firmwareSize = binSize;
          _isLoading = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _isLoading = false;
          _errorMessage = null; // No releases yet, not an error
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Failed to check for updates (HTTP ${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error: Could not reach GitHub.\n$e';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _startOtaUpdate() async {
    if (widget.characteristic == null || widget.device == null) {
      _showSnackBar('Not connected to robot!', isError: true);
      return;
    }
    if (!_isWifiConnected) {
      _showSnackBar('Robot is not connected to Wi-Fi!', isError: true);
      return;
    }
    if (_firmwareUrl == null) {
      _showSnackBar('No firmware file found in this release!', isError: true);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2128),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 12),
            Text('Confirm Update'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Before updating, make sure:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildCheckItem(Icons.wifi, 'Robot is connected to Wi-Fi'),
            const SizedBox(height: 8),
            _buildCheckItem(Icons.battery_charging_full, 'Robot has sufficient power'),
            const SizedBox(height: 8),
            _buildCheckItem(Icons.warning, 'Do NOT turn off the robot during update'),
            const SizedBox(height: 16),
            Text(
              'The robot will restart automatically after the update completes.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade400)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade400,
              foregroundColor: Colors.black,
            ),
            child: const Text('UPDATE NOW'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUpdating = true);

    try {
      final otaCommand = 'OTA:$_firmwareUrl';
      await widget.characteristic!
          .write(utf8.encode(otaCommand), withoutResponse: false)
          .timeout(const Duration(seconds: 10));
      _showSnackBar('Update command sent! Waiting for robot feedback...');
      
      // Safety timeout: if no feedback from robot in 2 minutes, reset state
      Future.delayed(const Duration(minutes: 2), () {
        if (mounted && _isUpdating) {
          setState(() => _isUpdating = false);
          _showSnackBar('Update timed out. Please check robot status.', isError: true);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        _showSnackBar('Failed to send OTA command: ${e.toString()}', isError: true);
      }
    }
  }

  Widget _buildCheckItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.tealAccent.shade400),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor:
            isError ? Colors.redAccent.shade700 : Colors.teal.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Software Update'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isUpdating ? null : _checkForUpdates,
            tooltip: 'Check Again',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingView()
            : _errorMessage != null
                ? _buildErrorView()
                : _latestVersion == null
                    ? _buildNoUpdateView()
                    : _buildUpdateAvailableView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.tealAccent.shade400,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Checking for updates...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Contacting GitHub...',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 80, color: Colors.redAccent.shade200),
            const SizedBox(height: 24),
            const Text(
              'Connection Error',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _checkForUpdates,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoUpdateView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.tealAccent.shade400.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline,
                  size: 80, color: Colors.tealAccent.shade400),
            ),
            const SizedBox(height: 24),
            const Text(
              'You\'re Up to Date!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'No firmware updates are available at this time.\nCheck back later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _checkForUpdates,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.tealAccent.shade400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('CHECK AGAIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateAvailableView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Update available banner
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.tealAccent.shade400
                          .withValues(alpha: 0.15 * _pulseAnimation.value),
                      Colors.blueAccent
                          .withValues(alpha: 0.1 * _pulseAnimation.value),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.tealAccent
                          .withValues(alpha: 0.4 * _pulseAnimation.value)),
                ),
                child: child,
              );
            },
            child: Column(
              children: [
                Icon(Icons.system_update,
                    size: 56, color: Colors.tealAccent.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Update Available!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'A new firmware version is ready to install.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Version info card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2128),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(Icons.label_outline, 'Version', _latestVersion!),
                const Divider(color: Colors.white10, height: 24),
                _buildInfoRow(
                    Icons.calendar_today, 'Released', _releaseDate ?? 'N/A'),
                if (_firmwareSize != null) ...[
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(
                      Icons.storage, 'Firmware Size', _firmwareSize!),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Release notes
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2128),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notes, color: Colors.tealAccent.shade400, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Release Notes',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _releaseNotes ?? 'No notes provided.',
                  style: TextStyle(
                      color: Colors.grey.shade300, fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // No firmware file warning
          if (_firmwareUrl == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      color: Colors.orangeAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No .bin firmware file found in this release. '
                      'The release author needs to attach a compiled .bin file.',
                      style: TextStyle(
                          color: Colors.orangeAccent.shade100, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          if (_firmwareUrl != null) ...[
            // Update button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: (_isUpdating || (_firmwareUrl == null) || (!_isWifiConnected && !_checkingWifi)) ? null : _startOtaUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade400,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: (_isUpdating || _checkingWifi)
                      ? Colors.tealAccent.shade400.withValues(alpha: 0.4)
                      : Colors.redAccent.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isUpdating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black54),
                          ),
                          SizedBox(width: 14),
                          Text('SENDING UPDATE COMMAND...',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              !_isWifiConnected && !_checkingWifi
                                  ? Icons.wifi_off
                                  : Icons.download_rounded,
                              size: 26,
                              color: !_isWifiConnected && !_checkingWifi ? Colors.redAccent : Colors.black),
                          const SizedBox(width: 12),
                          Text(
                              !_isWifiConnected && !_checkingWifi
                                  ? 'WIFI DISCONNECTED'
                                  : 'UPDATE ROBOT',
                              style: TextStyle(
                                  color: !_isWifiConnected && !_checkingWifi ? Colors.redAccent : Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                        ],
                      ),
              ),
            ),
            if (!_isWifiConnected && !_checkingWifi)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please connect robot to Wi-Fi first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent.shade100, fontSize: 13),
                ),
              ),

            const SizedBox(height: 16),

            // Info note
            Text(
              '⚡ Robot must be connected to Wi-Fi for OTA update.\n'
              '🔌 Do not power off the robot during the update process.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.tealAccent.shade400),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
