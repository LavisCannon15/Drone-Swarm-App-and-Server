import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../services/log_manager.dart';
import '../services/simulated_gps_service.dart';
import '../services/gps_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  late WebSocket _webSocket;
  bool isConnected = false;

  // Store telemetry data
  final Map<String, Map<String, dynamic>> telemetryData = {};

  // Store server logs
  final List<String> serverLogs = [];
  final StreamController<List<String>> _serverLogStreamController = StreamController.broadcast();
  Stream<List<String>> get serverLogStream => _serverLogStreamController.stream;

  // Timer for sending GPS updates
  Timer? _gpsUpdateTimer;

  // Connect to WebSocket server
  Future<void> connect(String url) async {
    try {
      _webSocket = await WebSocket.connect(url);
      isConnected = true;

      print("✅ Connected to WebSocket: $url");
      LogManager().addLog("✅ Connected to WebSocket: $url");

      // Subscribe to logs
      _webSocket.add(jsonEncode({"command": "subscribe_logs"}));

      _webSocket.listen(
        (data) => _handleIncomingMessage(data), // Process incoming messages
        onDone: () {
          print("🔌 WebSocket connection closed.");
          LogManager().addLog("🔌 WebSocket connection closed.");
          isConnected = false;
        },
        onError: (error) {
          print("❌ WebSocket error: $error");
          LogManager().addLog("❌ WebSocket error: $error.");
          isConnected = false;
        },
      );

      // ✅ Start sending GPS updates after connection
      _startSendingGPSData();
    } catch (e) {
      print("⚠️ Failed to connect to WebSocket: $e");
      LogManager().addLog("⚠️ Failed to connect to WebSocket: $e");
    }
  }

  // Start sending user GPS data to the server
  void _startSendingGPSData() {
    if (!isConnected) return;

    _gpsUpdateTimer?.cancel(); // Cancel any existing timer
    _gpsUpdateTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      final prefs = await SharedPreferences.getInstance();
      double offsetDistance = double.parse(prefs.getString('offsetDistance') ?? "4");
      double revolveSpeed = double.parse(prefs.getString('revolveSpeed') ?? "3");
      double revolveOffsetDistance = double.parse(prefs.getString('revolveOffsetDistance') ?? "4");
      double swapPositionSpeed = double.parse(prefs.getString('swapPositionSpeed') ?? "2");
      String selectedMode = prefs.getString('selectedMode') ?? "Normal";

      Map<String, dynamic> locationData;
      if (Platform.isAndroid || Platform.isIOS) {
        // Use the real GPSService on mobile devices
        // We use 'first' to get the latest data; note that this creates a one-time subscription each tick.
        locationData = await GPSService().locationStream.first;
      } else {
        // Use the simulated GPS service on other platforms
        locationData = await SimulatedGPSService().locationStream.first;
      }

      sendUserGPSData(
        latitude: locationData["latitude"],
        longitude: locationData["longitude"],
        speed: double.tryParse(locationData["speed"].toString()) ?? 0.0,
        offsetDistance: offsetDistance,
        revolveSpeed: revolveSpeed,
        revolveOffsetDistance: revolveOffsetDistance,
        swapPositionSpeed: swapPositionSpeed,
        selectedMode: selectedMode,
      );
    });
  }



  double lastLatitude = 0.0;
  double lastLongitude = 0.0;

  // Send user's GPS data
  void sendUserGPSData({
    required double latitude,
    required double longitude,
    required double speed,
    required double offsetDistance,
    required double revolveSpeed,
    required double revolveOffsetDistance,
    required double swapPositionSpeed,  // ✅ Include swapPositionSpeed
    required String selectedMode,
  }) {
    if (!isConnected) return;

    final message = {
      "command": "user_gps",
      "params": {
        "latitude": latitude,
        "longitude": longitude,
        "speed": speed,
        "offset_distance": offsetDistance,
        "revolve_speed": revolveSpeed,
        "revolve_offset_distance": revolveOffsetDistance,
        "swap_position_speed": swapPositionSpeed,  // ✅ Include swapPositionSpeed
        "orbit_around_user": selectedMode == "Orbit",
        "swap_positions": selectedMode == "Swap Positions",
        "rotate_triangle_formation": selectedMode == "Rotate Triangle"
      },
    };

    _webSocket.add(jsonEncode(message));

    //print("📡 Sent user GPS data: $message");
    //LogManager().addLog("📡 Sent user GPS data: $message");

    // ✅ Log only if user moves at least 5 meters
    if ((latitude - lastLatitude).abs() > 0.00005 || (longitude - lastLongitude).abs() > 0.00005) {
      LogManager().addLog("📜 Sent User Location Update: Lat=$latitude, Lng=$longitude, Speed=$speed");
      lastLatitude = latitude;
      lastLongitude = longitude;
    }
  }


  // Send start operations command (Takeoff)
  Future<void> sendStartOperations() async {
    if (!isConnected) {
      print("⚠️ WebSocket is not connected.");
      LogManager().addLog("⚠️ WebSocket is not connected.");
      return;
    }

    // ✅ Retrieve settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    String takeoffAltitude = prefs.getString('takeoffAltitude') ?? "3";
    String targetAltitude = prefs.getString('targetAltitude') ?? "1";
    String offsetDistance = prefs.getString('offsetDistance') ?? "4";
    String revolveSpeed = prefs.getString('revolveSpeed') ?? "3";
    String revolveOffsetDistance = prefs.getString('revolveOffsetDistance') ?? "4";
    String swapPositionSpeed = prefs.getString('swapPositionSpeed') ?? "1";  // ✅ Get Swap Position Speed
    String selectedMode = prefs.getString('selectedMode') ?? "Normal";

    // ✅ Prepare the data to send to the WebSocket server
    Map<String, dynamic> commandData = {
      "takeoff_altitude": double.parse(takeoffAltitude),
      "target_altitude": double.parse(targetAltitude),
      "offset_distance": double.parse(offsetDistance),
      "revolve_speed": double.parse(revolveSpeed),
      "revolve_offset_distance": double.parse(revolveOffsetDistance),
      "swap_position_speed": double.parse(swapPositionSpeed),  // ✅ Include swapPositionSpeed
      "orbit_around_user": selectedMode == "Orbit",
      "swap_positions": selectedMode == "Swap Positions",
      "rotate_triangle_formation": selectedMode == "Rotate Triangle"
    };

    // ✅ Send the command to the WebSocket server
    sendCommand("start_operations", commandData);

    print("🚀 Sent Start Operations Command: $commandData");
    LogManager().addLog("🚀 Sent Start Operations Command: $commandData");
  }

  // Send stop operations command (Landing)
  Future<void> sendStopOperations() async {
    if (!isConnected) {
      print("⚠️ WebSocket is not connected.");
      LogManager().addLog("⚠️ WebSocket is not connected.");
      return;
    }

    sendCommand("stop_operations", {});

    print("🛬 Sent Stop Operations Command");
    LogManager().addLog("🛬 Sent Stop Operations Command");
  }


  // Send command to WebSocket server
  Future<void> sendCommand(String command, Map<String, dynamic> params) async {
    if (!isConnected) {
      print("⚠️ WebSocket not connected.");
      LogManager().addLog("⚠️ WebSocket not connected.");
      return;
    }
    final message = {
      "command": command,
      "params": params,
    };
    _webSocket.add(jsonEncode(message));

    print("🚀 Sent command: $message");
    LogManager().addLog("🚀 Sent command: $message");
  }

  // Send connection requests to drones
  Future<void> connectToDrones(List<String> droneConnections) async {
    if (!isConnected) {
      print("⚠️ WebSocket not connected.");
      LogManager().addLog("⚠️ WebSocket not connected.");
      return;
    }

    try {
      final message = {
        "command": "connect",
        "params": {"drones": droneConnections},
      };
      _webSocket.add(jsonEncode(message));

      print("🔗 Drone connection requests sent: $droneConnections");
      LogManager().addLog("🔗 Drone connection requests sent: $droneConnections");
    } catch (e) {
      print("❌ Error sending drone connection requests: $e");
      LogManager().addLog("❌ Error sending drone connection requests: $e");
    }
  }

  // Handle incoming WebSocket messages
  void _handleIncomingMessage(String data) {
    try {
      final message = jsonDecode(data);

      if (message["command"] == "telemetry") {
        // Parse telemetry data
        final List<dynamic> telemetryList = message["data"];
        telemetryData.clear(); // Clear old telemetry data

        for (var drone in telemetryList) {
          telemetryData[drone["drone_id"]] = Map<String, dynamic>.from(drone);
        }

        //print("📡 Telemetry updated: $telemetryData");
        //LogManager().addLog("📡 Telemetry updated: $telemetryData");
      } else if (message["command"] == "log") {
        // Handle server logs
        String logMessage = message["message"];
        serverLogs.add(logMessage);
        _serverLogStreamController.add(List.from(serverLogs));

        print("📜 Server Log: $logMessage");
        LogManager().addLog("📜 Server Log: $logMessage");
      } else {
        print("📩 Received: $message");
        LogManager().addLog("📩 Received: $message");
      }
    } catch (e) {
      print("❌ Failed to decode WebSocket message: $e");
      LogManager().addLog("❌ Failed to decode WebSocket message: $e");
    }
  }

  // Disconnect WebSocket
  Future<void> disconnect() async {
    if (isConnected) {
      await _webSocket.close();
      isConnected = false;
      _gpsUpdateTimer?.cancel(); // Stop GPS updates

      print("🔌 Disconnected from WebSocket.");
      LogManager().addLog("🔌 Disconnected from WebSocket.");
    }
  }
}
