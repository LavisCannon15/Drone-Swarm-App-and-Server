import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../services/log_manager.dart';

import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Default values for settings
  final Map<String, String> defaultSettings = {
    "takeoffAltitude": "1",
    "initialPositionSpeed": "3",
    "targetAltitude": "1",
    "offsetDistance": "4",
    "revolveSpeed": "2",
    "revolveOffsetDistance": "4",
    "swapPositionSpeed": "1",
    "simSpeed": "1",
    "simMaxDistance": "20",
    "serverAddress": "127.0.0.1:5000",
  };

  // Current values for settings
  String takeoffAltitude = "3";
  String initialPositionSpeed = "3";
  String targetAltitude = "1";
  String offsetDistance = "4";
  String revolveSpeed = "2";
  String revolveOffsetDistance = "4";
  String swapPositionSpeed = "1";
  String simSpeed = "1";
  String simMaxDistance = "20";
  String serverAddress = "127.0.0.1:5000";

  late final TextEditingController takeoffAltitudeController;
  late final TextEditingController initialPositionSpeedController;
  late final TextEditingController targetAltitudeController;
  late final TextEditingController offsetDistanceController;
  late final TextEditingController revolveSpeedController;
  late final TextEditingController revolveOffsetDistanceController;
  late final TextEditingController swapPositionSpeedController;
  late final TextEditingController simSpeedController;
  late final TextEditingController simMaxDistanceController;
  late final TextEditingController serverAddressController;

  @override
  void initState() {
    super.initState();
    takeoffAltitudeController = TextEditingController();
    initialPositionSpeedController = TextEditingController();
    targetAltitudeController = TextEditingController();
    offsetDistanceController = TextEditingController();
    revolveSpeedController = TextEditingController();
    revolveOffsetDistanceController = TextEditingController();
    swapPositionSpeedController = TextEditingController();
    simSpeedController = TextEditingController();
    simMaxDistanceController = TextEditingController();
    serverAddressController = TextEditingController();
    _loadSettings(); // Load saved settings
  }

  @override
  void dispose() {
    takeoffAltitudeController.dispose();
    initialPositionSpeedController.dispose();
    targetAltitudeController.dispose();
    offsetDistanceController.dispose();
    revolveSpeedController.dispose();
    revolveOffsetDistanceController.dispose();
    swapPositionSpeedController.dispose();
    simSpeedController.dispose();
    simMaxDistanceController.dispose();
    serverAddressController.dispose();
    super.dispose();
  }

  String _sanitizeServerAddress(String value) {
    return value.replaceFirst(RegExp(r'^wss?://'), '');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      takeoffAltitude =
          prefs.getString('takeoffAltitude') ?? defaultSettings['takeoffAltitude']!;
      initialPositionSpeed =
          prefs.getString('initialPositionSpeed') ?? defaultSettings['initialPositionSpeed']!;
      targetAltitude =
          prefs.getString('targetAltitude') ?? defaultSettings['targetAltitude']!;
      offsetDistance =
          prefs.getString('offsetDistance') ?? defaultSettings['offsetDistance']!;
      revolveSpeed =
          prefs.getString('revolveSpeed') ?? defaultSettings['revolveSpeed']!;
      revolveOffsetDistance =
          prefs.getString('revolveOffsetDistance') ?? defaultSettings['revolveOffsetDistance']!;
      swapPositionSpeed =
          prefs.getString('swapPositionSpeed') ?? defaultSettings['swapPositionSpeed']!;
      simSpeed =
          prefs.getString('simSpeed') ?? defaultSettings['simSpeed']!;
      simMaxDistance =
          prefs.getString('simMaxDistance') ?? defaultSettings['simMaxDistance']!;
      serverAddress = _sanitizeServerAddress(
          prefs.getString('serverAddress') ?? defaultSettings['serverAddress']!);

      takeoffAltitudeController.text = takeoffAltitude;
      initialPositionSpeedController.text = initialPositionSpeed;
      targetAltitudeController.text = targetAltitude;
      offsetDistanceController.text = offsetDistance;
      revolveSpeedController.text = revolveSpeed;
      revolveOffsetDistanceController.text = revolveOffsetDistance;
      swapPositionSpeedController.text = swapPositionSpeed;
      simSpeedController.text = simSpeed;
      simMaxDistanceController.text = simMaxDistance;
      serverAddressController.text = serverAddress;
    });

  
    if (kDebugMode) {
        print(
            "📥 Loaded settings: takeoffAltitude=$takeoffAltitude, initialPositionSpeed=$initialPositionSpeed, targetAltitude=$targetAltitude, offsetDistance=$offsetDistance, revolveSpeed=$revolveSpeed, revolveOffsetDistance=$revolveOffsetDistance, swapPositionSpeed=$swapPositionSpeed, simSpeed=$simSpeed, simMaxDistance=$simMaxDistance, serverAddress=$serverAddress");
    }
    LogManager().addLog(
        "📥 Loaded settings: takeoffAltitude=$takeoffAltitude, initialPositionSpeed=$initialPositionSpeed, targetAltitude=$targetAltitude, offsetDistance=$offsetDistance, revolveSpeed=$revolveSpeed, revolveOffsetDistance=$revolveOffsetDistance, swapPositionSpeed=$swapPositionSpeed, simSpeed=$simSpeed, simMaxDistance=$simMaxDistance, serverAddress=$serverAddress");
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('takeoffAltitude', takeoffAltitude);
      await prefs.setString('targetAltitude', targetAltitude);
      await prefs.setString('initialPositionSpeed', initialPositionSpeed);
      await prefs.setString('offsetDistance', offsetDistance);
      await prefs.setString('revolveSpeed', revolveSpeed);
      await prefs.setString('revolveOffsetDistance', revolveOffsetDistance);
      await prefs.setString('swapPositionSpeed', swapPositionSpeed);
      await prefs.setString('simSpeed', simSpeed);
      await prefs.setString('simMaxDistance', simMaxDistance);
      await prefs.setString('serverAddress', _sanitizeServerAddress(serverAddress));

    // Refresh caches so new values apply immediately
    await GPSService().refreshSettings();
    await SimulatedGPSService().refreshSettings();

    LogManager().addLog('💾 Settings saved!');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _resetToDefault() async {
    setState(() {
      takeoffAltitude = defaultSettings['takeoffAltitude']!;
      initialPositionSpeed = defaultSettings['initialPositionSpeed']!;
      targetAltitude = defaultSettings['targetAltitude']!;
      offsetDistance = defaultSettings['offsetDistance']!;
      revolveSpeed = defaultSettings['revolveSpeed']!;
      revolveOffsetDistance = defaultSettings['revolveOffsetDistance']!;
      swapPositionSpeed = defaultSettings['swapPositionSpeed']!;
      simSpeed = defaultSettings['simSpeed']!;
      simMaxDistance = defaultSettings['simMaxDistance']!;
      serverAddress =
          _sanitizeServerAddress(defaultSettings['serverAddress']!);

      takeoffAltitudeController.text = takeoffAltitude;
      initialPositionSpeedController.text = initialPositionSpeed;
      targetAltitudeController.text = targetAltitude;
      offsetDistanceController.text = offsetDistance;
      revolveSpeedController.text = revolveSpeed;
      revolveOffsetDistanceController.text = revolveOffsetDistance;
      swapPositionSpeedController.text = swapPositionSpeed;
      simSpeedController.text = simSpeed;
      simMaxDistanceController.text = simMaxDistance;
      serverAddressController.text = serverAddress;
    });

    await _saveSettings(); // Save default values

    if (kDebugMode) {
      print("🔄 Settings reset to default!");
    }
    LogManager().addLog("🔄 Settings reset to default!");
  }

  // ✅ Function to Clear FMTC Cache
  Future<void> _clearCache() async {
    try {
      await FMTCStore('carto_cache').manage.reset();
      if (kDebugMode) {
        print("🗑️ Cache cleared!");
      }
      LogManager().addLog("🗑️ Cache cleared successfully!");
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Cache cleared successfully!")));
    } catch (e) {
      if (kDebugMode) {
        print("❌ Failed to clear cache: $e");
      }
      LogManager().addLog("❌ Failed to clear cache: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to clear cache!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Takeoff Settings
            Text(
              "Takeoff Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            // Takeoff Altitude
            TextField(
              decoration: InputDecoration(
                labelText: "Takeoff Altitude",
                hintText: "Enter takeoff altitude (meters)",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => takeoffAltitude = value,
              controller: takeoffAltitudeController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Initial Position Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Initial Position Speed",
                hintText: "Speed to initial position (m/s)",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => initialPositionSpeed = value,
              controller: initialPositionSpeedController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 20),
            // Formation Settings
            Text(
              "Formation Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            // Target Altitude
            TextField(
              decoration: InputDecoration(
                labelText: "Target Altitude",
                hintText: "Enter target altitude (meters)",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => targetAltitude = value,
              controller: targetAltitudeController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Offset Distance
            TextField(
              decoration: InputDecoration(
                labelText: "Offset Distance",
                hintText: "Enter offset distance (meters)",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => offsetDistance = value,
              controller: offsetDistanceController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Revolve Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Revolve Speed",
                hintText: "Enter angle increment",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => revolveSpeed = value,
              controller: revolveSpeedController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Revolve Offset Distance
            TextField(
              decoration: InputDecoration(
                labelText: "Revolve Offset Distance",
                hintText: "Enter revolve offset distance (meters)",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => revolveOffsetDistance = value,
              controller: revolveOffsetDistanceController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Swap Position Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Swap Position Speed",
                hintText: "Enter swap position speed",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => swapPositionSpeed = value,
              controller: swapPositionSpeedController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 20),
            // Simulated Movement Settings
            Text(
              "Simulated Movement",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            // Simulated Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Simulated Speed",
                hintText: "Meters per second",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => simSpeed = value,
              controller: simSpeedController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Simulated Max Distance
            TextField(
              decoration: InputDecoration(
                labelText: "Simulated Max Distance",
                hintText: "Meters",
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => simMaxDistance = value,
              controller: simMaxDistanceController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^[0-9]*\.?[0-9]*$'),
                ),
              ],
            ),
            SizedBox(height: 20),
            // Server Settings
            Text(
              "Server Settings",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            // Server Address
            TextField(
              decoration: InputDecoration(
                labelText: "Server Address",
                hintText: "Enter server address (e.g., 192.168.1.1:5000)",
              ),
              keyboardType: TextInputType.text,
              onChanged: (value) => serverAddress = _sanitizeServerAddress(value),
              controller: serverAddressController,
            ),
            SizedBox(height: 20),
            // Save Button
            ElevatedButton(
              onPressed: () async {
                await _saveSettings(); // <— only pop inside _saveSettings
              },
              child: Text("Save Settings"),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _resetToDefault,
              child: Text("Reset to Default"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
            ),
            // ✅ Show "Clear Cache" button only on DESKTOP platforms (Linux, Windows, Mac)
            if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.linux ||
                    defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.macOS)) ...[
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _clearCache,
                child: Text("Clear Map Cache"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
