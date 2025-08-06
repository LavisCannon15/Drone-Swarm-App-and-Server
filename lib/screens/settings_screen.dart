import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'dart:io';
import '../services/log_manager.dart';

import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Default values for settings
  final Map<String, String> defaultSettings = {
    "takeoffAltitude": "1",
    "targetAltitude": "1",
    "offsetDistance": "4",
    "revolveSpeed": "20",
    "revolveOffsetDistance": "4",
    "swapPositionSpeed": "1",
    "serverAddress": "ws://127.0.0.1:5000",
  };

  // Current values for settings
  String takeoffAltitude = "3";
  String targetAltitude = "1";
  String offsetDistance = "4";
  String revolveSpeed = "20";
  String revolveOffsetDistance = "4";
  String swapPositionSpeed = "1";
  String serverAddress = "ws://127.0.0.1:5000";

  late final TextEditingController takeoffAltitudeController;
  late final TextEditingController targetAltitudeController;
  late final TextEditingController offsetDistanceController;
  late final TextEditingController revolveSpeedController;
  late final TextEditingController revolveOffsetDistanceController;
  late final TextEditingController swapPositionSpeedController;
  late final TextEditingController serverAddressController;

  @override
  void initState() {
    super.initState();
    takeoffAltitudeController = TextEditingController();
    targetAltitudeController = TextEditingController();
    offsetDistanceController = TextEditingController();
    revolveSpeedController = TextEditingController();
    revolveOffsetDistanceController = TextEditingController();
    swapPositionSpeedController = TextEditingController();
    serverAddressController = TextEditingController();
    _loadSettings(); // Load saved settings
  }

  @override
  void dispose() {
    takeoffAltitudeController.dispose();
    targetAltitudeController.dispose();
    offsetDistanceController.dispose();
    revolveSpeedController.dispose();
    revolveOffsetDistanceController.dispose();
    swapPositionSpeedController.dispose();
    serverAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      takeoffAltitude =
          prefs.getString('takeoffAltitude') ?? defaultSettings['takeoffAltitude']!;
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
      serverAddress =
          prefs.getString('serverAddress') ?? defaultSettings['serverAddress']!;

      takeoffAltitudeController.text = takeoffAltitude;
      targetAltitudeController.text = targetAltitude;
      offsetDistanceController.text = offsetDistance;
      revolveSpeedController.text = revolveSpeed;
      revolveOffsetDistanceController.text = revolveOffsetDistance;
      swapPositionSpeedController.text = swapPositionSpeed;
      serverAddressController.text = serverAddress;
    });

    print(
        "📥 Loaded settings: takeoffAltitude=$takeoffAltitude, targetAltitude=$targetAltitude, offsetDistance=$offsetDistance, revolveSpeed=$revolveSpeed, revolveOffsetDistance=$revolveOffsetDistance, swapPositionSpeed=$swapPositionSpeed, serverAddress=$serverAddress");
    LogManager().addLog(
        "📥 Loaded settings: takeoffAltitude=$takeoffAltitude, targetAltitude=$targetAltitude, offsetDistance=$offsetDistance, revolveSpeed=$revolveSpeed, revolveOffsetDistance=$revolveOffsetDistance, swapPositionSpeed=$swapPositionSpeed, serverAddress=$serverAddress");
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('takeoffAltitude', takeoffAltitude);
    await prefs.setString('targetAltitude', targetAltitude);
    await prefs.setString('offsetDistance', offsetDistance);
    await prefs.setString('revolveSpeed', revolveSpeed);
    await prefs.setString('revolveOffsetDistance', revolveOffsetDistance);
    await prefs.setString('swapPositionSpeed', swapPositionSpeed);
    await prefs.setString('serverAddress', serverAddress);

    // Refresh caches so new values apply immediately
    await GPSService().refreshSettings();
    await SimulatedGPSService().refreshSettings();

    LogManager().addLog('💾 Settings saved!');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _resetToDefault() async {
    setState(() {
      takeoffAltitude = defaultSettings['takeoffAltitude']!;
      targetAltitude = defaultSettings['targetAltitude']!;
      offsetDistance = defaultSettings['offsetDistance']!;
      revolveSpeed = defaultSettings['revolveSpeed']!;
      revolveOffsetDistance = defaultSettings['revolveOffsetDistance']!;
      swapPositionSpeed = defaultSettings['swapPositionSpeed']!;
      serverAddress = defaultSettings['serverAddress']!;

      takeoffAltitudeController.text = takeoffAltitude;
      targetAltitudeController.text = targetAltitude;
      offsetDistanceController.text = offsetDistance;
      revolveSpeedController.text = revolveSpeed;
      revolveOffsetDistanceController.text = revolveOffsetDistance;
      swapPositionSpeedController.text = swapPositionSpeed;
      serverAddressController.text = serverAddress;
    });

    await _saveSettings(); // Save default values

    print("🔄 Settings reset to default!");
    LogManager().addLog("🔄 Settings reset to default!");
  }

  // ✅ Function to Clear FMTC Cache
  Future<void> _clearCache() async {
    try {
      await FMTCStore('carto_cache').manage.reset();
      print("🗑️ Cache cleared!");
      LogManager().addLog("🗑️ Cache cleared successfully!");
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Cache cleared successfully!")));
    } catch (e) {
      print("❌ Failed to clear cache: $e");
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
            // Takeoff Altitude
            TextField(
              decoration: InputDecoration(
                labelText: "Takeoff Altitude",
                hintText: "Enter takeoff altitude (meters)",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => takeoffAltitude = value,
              controller: takeoffAltitudeController,
            ),
            SizedBox(height: 10),
            // Target Altitude
            TextField(
              decoration: InputDecoration(
                labelText: "Target Altitude",
                hintText: "Enter target altitude (meters)",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => targetAltitude = value,
              controller: targetAltitudeController,
            ),
            SizedBox(height: 10),
            // Offset Distance
            TextField(
              decoration: InputDecoration(
                labelText: "Offset Distance",
                hintText: "Enter offset distance (meters)",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => offsetDistance = value,
              controller: offsetDistanceController,
            ),
            SizedBox(height: 10),
            // Revolve Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Revolve Speed",
                hintText: "Enter angle increment",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => revolveSpeed = value,
              controller: revolveSpeedController,
            ),
            SizedBox(height: 10),
            // Revolve Offset Distance
            TextField(
              decoration: InputDecoration(
                labelText: "Revolve Offset Distance",
                hintText: "Enter revolve offset distance (meters)",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => revolveOffsetDistance = value,
              controller: revolveOffsetDistanceController,
            ),
            SizedBox(height: 10),
            // Swap Position Speed
            TextField(
              decoration: InputDecoration(
                labelText: "Swap Position Speed",
                hintText: "Enter swap position speed",
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) => swapPositionSpeed = value,
              controller: swapPositionSpeedController,
            ),
            SizedBox(height: 10),
            // Server Address
            TextField(
              decoration: InputDecoration(
                labelText: "Server Address",
                hintText: "Enter WebSocket server URL (e.g., ws://192.168.1.1:5000)",
              ),
              keyboardType: TextInputType.text,
              onChanged: (value) => serverAddress = value,
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
            if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) ...[
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
