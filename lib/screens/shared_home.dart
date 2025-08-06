import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import '../widgets/desktop_map_widget.dart';
import '../services/log_manager.dart';
import '../widgets/map_widget.dart';
import '../widgets/telemetry_widget.dart';
import '../widgets/mode_selector.dart';
import '../widgets/connect_button.dart';
import '../widgets/takeoff_land_button.dart';
import '../widgets/recenter_button.dart';
import '../widgets/drone_info_bottom_sheet.dart';
import '../widgets/xy_graph_widget.dart';
import '../widgets/map_type_button.dart';
import 'settings_screen.dart';
import 'drone_management_screen.dart';
import 'console_screen.dart';
import '../services/websocket_service.dart';

class SharedHome extends StatefulWidget {
  @override
  _SharedHomeState createState() => _SharedHomeState();
}

class _SharedHomeState extends State<SharedHome> {
  final GlobalKey<DesktopMapWidgetState> desktopMapKey =
      GlobalKey<DesktopMapWidgetState>();
  final GlobalKey<MapWidgetState> mobileMapKey = GlobalKey<MapWidgetState>();

  bool isMapView = true;

  @override
  void initState() {
    super.initState();

    print("🔥 SharedHome initialized!");
    LogManager().addLog("📡 SharedHome loaded successfully.");

    initializeBackgroundExecution();
  }

  Future<void> initializeBackgroundExecution() async {
    if (Platform.isAndroid) {
      final isEnabled = await FlutterBackground.isBackgroundExecutionEnabled;
      if (!isEnabled) {
        bool success = await FlutterBackground.initialize();
        if (success) {
          FlutterBackground.enableBackgroundExecution();
        } else {
          print("❌ Failed to enable background execution.");
          LogManager().addLog("❌ Failed to enable background execution.");
        }
      }
    }
  }

  @override
  void dispose() {
    WebSocketService().dispose();
    LogManager().dispose();
    if (Platform.isAndroid) {
      FlutterBackground.disableBackgroundExecution();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print("🔄 SharedHome is rebuilding");
    }
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: Colors.blue,
              padding: EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
              child: Text(
                "Menu",
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text("Settings"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.add),
              title: Text("Manage Drones"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => DroneManagementScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.terminal),
              title: Text("Console"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ConsoleScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          isMapView
              ? (Platform.isAndroid
                  ? MapWidget(key: mobileMapKey)
                  : DesktopMapWidget(key: desktopMapKey))
              : XYGraphWidget(),
          DroneInfoBottomSheet(),
          Positioned(
            top: 50,
            left: 20,
            child: Builder(
              builder: (BuildContext context) {
                return GestureDetector(
                  onTap: () {
                    Scaffold.of(context).openDrawer();
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.menu,
                      color: Colors.black,
                      size: 30,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 50,
            right: 10,
            child: TelemetryWidget(),
          ),
          Positioned(
            bottom: 180,
            right: 20,
            child: MapTypeButton(
              isMapView: isMapView,
              onToggle: (bool value) {
                setState(() {
                  isMapView = value;
                });
              },
            ),
          ),
          Positioned(
            bottom: 120,
            left: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModeSelector(
                    onModeSelected: (mode) => print("Mode Selected: $mode")),
                SizedBox(height: 20),
                TakeOffLandButton(),
                SizedBox(height: 20),
                ConnectButton(),
              ],
            ),
          ),
          Positioned(
            bottom: 120,
            right: 20,
            child: RecenterButton(
              desktopMapKey: desktopMapKey,
              mobileMapKey: mobileMapKey,
            ),
          ),
        ],
      ),
    );
  }
}
