import 'dart:async';
import 'dart:convert';
import '../services/log_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  late WebSocketChannel _webSocket;
  bool isConnected = false;

  // Connection status stream
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStatusStream =>
      _connectionStatusController.stream;

  String? _lastUrl;
  int _retryCount = 0;
  final int _maxRetries = 5;
  bool _isReconnecting = false;
  void Function(int attempt, Duration delay)? onReconnectionAttempt;

  // ─── Telemetry stream ────────────────────────────────────────────────────────
  final StreamController<void> _telemetryStreamController =
      StreamController.broadcast();
  Stream<void> get telemetryStream => _telemetryStreamController.stream;

  // Store telemetry data
  final Map<String, Map<String, dynamic>> telemetryData = {};

  // Store server logs (capped)
  final List<String> serverLogs = [];
  final StreamController<List<String>> _serverLogStreamController =
      StreamController.broadcast();
  Stream<List<String>> get serverLogStream => _serverLogStreamController.stream;
  static const int _maxServerLogs = 500;

  void addServerLog(String logMessage) {
    serverLogs.add(logMessage);
    if (serverLogs.length > _maxServerLogs) {
      serverLogs.removeRange(0, serverLogs.length - _maxServerLogs);
    }
    _serverLogStreamController.add(List.from(serverLogs));
  }

  void clearServerLogs() {
    serverLogs.clear();
    _serverLogStreamController.add([]);
  }

  // Connect to WebSocket server
  Future<void> connect(String url) async {
    _lastUrl = url;
    _retryCount = 0;
    final connected = await _attemptConnection(url);
    if (!connected) {
      await _retryConnection();
    }
  }

  Future<bool> _attemptConnection(String url) async {
    try {
       _webSocket = WebSocketChannel.connect(Uri.parse(url));
      isConnected = true;
      _connectionStatusController.add(true);

      if (kDebugMode) {
        print("✅ Connected to WebSocket: $url");
      }
      LogManager().addLog("✅ Connected to WebSocket: $url");

      // Subscribe to logs
      _webSocket.sink.add(jsonEncode({"command": "subscribe_logs"}));

      _webSocket.stream.listen(
        (data) => _handleIncomingMessage(data), // Process incoming messages
        onDone: () {
          if (kDebugMode) {
            print("🔌 WebSocket connection closed.");
          }
          LogManager().addLog("🔌 WebSocket connection closed.");
          _handleDisconnect();
        },
        onError: (error) {
          if (kDebugMode) {
            print("❌ WebSocket error: $error");
          }
          LogManager().addLog("❌ WebSocket error: $error.");
          _handleDisconnect();
        },
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("⚠️ Failed to connect to WebSocket: $e");
      }
      LogManager().addLog("⚠️ Failed to connect to WebSocket: $e");
      isConnected = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  void _handleDisconnect() {
    isConnected = false;
    _connectionStatusController.add(false);
    _retryConnection();
  }

  Future<void> _retryConnection() async {
    if (_isReconnecting || _lastUrl == null) return;
    _isReconnecting = true;

    while (_retryCount < _maxRetries && !isConnected) {
      final delay = Duration(seconds: 1 << _retryCount);
      onReconnectionAttempt?.call(_retryCount + 1, delay);
      final message =
          "🔄 Attempting to reconnect (#${_retryCount + 1}) in ${delay.inSeconds}s";
      if (kDebugMode) {
        print(message);
      }
      LogManager().addLog(message);
      await Future.delayed(delay);
      final success = await _attemptConnection(_lastUrl!);
      if (success) {
        _retryCount = 0;
        break;
      }
      _retryCount++;
    }

    if (!isConnected) {
      final message =
          "❌ Failed to reconnect after $_maxRetries attempts.";
      if (kDebugMode) {
        print(message);
      }
      LogManager().addLog(message);
    }

    _isReconnecting = false;
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
    required double swapPositionSpeed,
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
        "swap_position_speed": swapPositionSpeed,
        "orbit_around_user": selectedMode == "Orbit",
        "swap_positions": selectedMode == "Swap Positions",
        "rotate_triangle_formation": selectedMode == "Rotate Triangle"
      },
    };

    _webSocket.sink.add(jsonEncode(message));

    if ((latitude - lastLatitude).abs() > 0.00005 ||
        (longitude - lastLongitude).abs() > 0.00005) {
      LogManager().addLog(
          "📜 Sent User Location Update: Lat=$latitude, Lng=$longitude, Speed=$speed");
      lastLatitude = latitude;
      lastLongitude = longitude;
    }
  }

  // Send start operations command (Takeoff)
  Future<void> sendStartOperations() async {
    if (!isConnected) {
      if (kDebugMode) {
        print("⚠️ WebSocket is not connected.");
      }
      LogManager().addLog("⚠️ WebSocket is not connected.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    String takeoffAltitude = prefs.getString('takeoffAltitude') ?? "3";
    String targetAltitude = prefs.getString('targetAltitude') ?? "1";
    String offsetDistance = prefs.getString('offsetDistance') ?? "4";
    String revolveSpeed = prefs.getString('revolveSpeed') ?? "3";
    String revolveOffsetDistance =
        prefs.getString('revolveOffsetDistance') ?? "4";
    String swapPositionSpeed = prefs.getString('swapPositionSpeed') ?? "1";
    String selectedMode = prefs.getString('selectedMode') ?? "Normal";

    double _parseParam(String value, double defaultValue, String name) {
      final parsed = double.tryParse(value);
      if (parsed == null) {
        final message =
            "⚠️ Invalid $name value '$value'. Using default $defaultValue.";
        if (kDebugMode) {
          print(message);
        }
        LogManager().addLog(message);
        return defaultValue;
      }
      return parsed;
    }


    Map<String, dynamic> commandData = {
      "takeoff_altitude": _parseParam(takeoffAltitude, 3.0, 'takeoff_altitude'),
      "target_altitude": _parseParam(targetAltitude, 1.0, 'target_altitude'),
      "offset_distance": _parseParam(offsetDistance, 4.0, 'offset_distance'),
      "revolve_speed": _parseParam(revolveSpeed, 3.0, 'revolve_speed'),
      "revolve_offset_distance":
          _parseParam(revolveOffsetDistance, 4.0, 'revolve_offset_distance'),
      "swap_position_speed":
          _parseParam(swapPositionSpeed, 1.0, 'swap_position_speed'),
      "orbit_around_user": selectedMode == "Orbit",
      "swap_positions": selectedMode == "Swap Positions",
      "rotate_triangle_formation": selectedMode == "Rotate Triangle"
    };

    sendCommand("start_operations", commandData);

    if (kDebugMode) {
      print("🚀 Sent Start Operations Command: $commandData");
    }
    LogManager().addLog("🚀 Sent Start Operations Command: $commandData");
  }

  // Send stop operations command (Landing)
  Future<void> sendStopOperations() async {
    if (!isConnected) {
      if (kDebugMode) {
        print("⚠️ WebSocket is not connected.");
      }
      LogManager().addLog("⚠️ WebSocket is not connected.");
      return;
    }

    sendCommand("stop_operations", {});

    if (kDebugMode) {
      print("🛬 Sent Stop Operations Command");
    }
    LogManager().addLog("🛬 Sent Stop Operations Command");
  }

  // Send command to WebSocket server
  Future<void> sendCommand(String command, Map<String, dynamic> params) async {
    if (!isConnected) {
      if (kDebugMode) {
        print("⚠️ WebSocket not connected.");
      }
      LogManager().addLog("⚠️ WebSocket not connected.");
      return;
    }
    final message = {
      "command": command,
      "params": params,
    };
    _webSocket.sink.add(jsonEncode(message));

    if (kDebugMode) {
      print("🚀 Sent command: $message");
    }
    LogManager().addLog("🚀 Sent command: $message");
  }

  // Send connection requests to drones
  Future<void> connectToDrones(List<String> droneConnections) async {
    if (!isConnected) {
      if (kDebugMode) {
        print("⚠️ WebSocket not connected.");
      }
      LogManager().addLog("⚠️ WebSocket not connected.");
      return;
    }

    try {
      final message = {
        "command": "connect",
        "params": {"drones": droneConnections},
      };
      _webSocket.sink.add(jsonEncode(message));

      if (kDebugMode) {
        print("🔗 Drone connection requests sent: $droneConnections");
      }
      LogManager().addLog("🔗 Drone connection requests sent: $droneConnections");
    } catch (e) {
      if (kDebugMode) {
        print("❌ Error sending drone connection requests: $e");
      }
      LogManager().addLog("❌ Error sending drone connection requests: $e");
    }
  }

  // Handle incoming WebSocket messages
  void _handleIncomingMessage(String data) {
    try {
      final message = jsonDecode(data);

      if (message["command"] == "telemetry") {
        final List<dynamic> telemetryList = message["data"];
        telemetryData
          ..clear()
          ..addEntries(telemetryList.map((drone) =>
              MapEntry(drone["drone_id"], Map<String, dynamic>.from(drone))));
        _telemetryStreamController.add(null); // notify listeners
      } else if (message["command"] == "log") {
        String logMessage = message["message"];
        addServerLog(logMessage);

        if (kDebugMode) {
          print("📜 Server Log: $logMessage");
        }
        LogManager().addLog("📜 Server Log: $logMessage");
      } else {

        if (kDebugMode) {
          print("📩 Received: $message");
        }
        LogManager().addLog("📩 Received: $message");
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Failed to decode WebSocket message: $e");
      }
      LogManager().addLog("❌ Failed to decode WebSocket message: $e");
    }
  }

  // Disconnect WebSocket
  Future<void> disconnect() async {
    _lastUrl = null;
    _isReconnecting = false;
    if (isConnected) {
      await _webSocket.sink.close();
      isConnected = false;
      _connectionStatusController.add(false);
      if (kDebugMode) {
        print("🔌 Disconnected from WebSocket.");
      }
      LogManager().addLog("🔌 Disconnected from WebSocket.");
    }
  }

  void dispose() {
    _telemetryStreamController.close();
    _serverLogStreamController.close();
    _connectionStatusController.close();
  }
}

