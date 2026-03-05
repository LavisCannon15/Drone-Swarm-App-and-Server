import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/log_manager.dart';
import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
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
  DateTime? _lastLocalModeSelectionAt;
  String? _lastLocalModeSelection;
  static const Duration _localModeSelectionGracePeriod =
      Duration(seconds: 3);
  void Function(int attempt, Duration delay)? onReconnectionAttempt;

  // ─── Telemetry stream ────────────────────────────────────────────────────────
  final StreamController<void> _telemetryStreamController =
      StreamController.broadcast();
  Stream<void> get telemetryStream => _telemetryStreamController.stream;

  // Store telemetry data
  final Map<String, Map<String, dynamic>> telemetryData = {};

  // Store server logs (capped)
  final List<String> serverLogs = [];
  final StreamController<String> _serverLogStreamController =
      StreamController.broadcast();
  Stream<String> get serverLogStream => _serverLogStreamController.stream;
  static const int _maxServerLogs = 500;

  // Store drone status text per drone
  final Map<String, List<String>> droneStatus = {};
  final StreamController<void> _droneStatusStreamController =
      StreamController.broadcast();
  Stream<void> get droneStatusStream => _droneStatusStreamController.stream;
  static const int _maxStatusLogs = 200;

  // Landing completion stream
  final StreamController<void> _landingCompleteStreamController =
      StreamController.broadcast();
  Stream<void> get landingCompleteStream =>
      _landingCompleteStreamController.stream;

  // Emergency stop stream
  final StreamController<void> _emergencyStopStreamController =
      StreamController.broadcast();
  Stream<void> get emergencyStopStream =>
      _emergencyStopStreamController.stream;

  void addServerLog(String logMessage) {
    serverLogs.add(logMessage);
    if (serverLogs.length > _maxServerLogs) {
      serverLogs.removeAt(0);
    }
    _serverLogStreamController.add(logMessage);
  }

  void clearServerLogs() {
    serverLogs.clear();
  }

  void addDroneStatus(String droneId, String message) {
    final logs = droneStatus.putIfAbsent(droneId, () => []);
    logs.add(message);
    if (logs.length > _maxStatusLogs) {
      logs.removeAt(0);
    }
    _droneStatusStreamController.add(null);
  }

  void clearDroneStatus(String droneId) {
    droneStatus[droneId]?.clear();
    _droneStatusStreamController.add(null);
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
      final socket = await WebSocket.connect(url);
      _webSocket = IOWebSocketChannel(socket);
      isConnected = true;
      _connectionStatusController.add(true);

      if (kDebugMode) {
        print("✅ Connected to WebSocket: $url");
      }
      LogManager().addLog("✅ Connected to WebSocket: $url");

      _webSocket.stream.listen(
        (data) async => await _handleIncomingMessage(data),
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

      // Subscribe to logs and drone status text
      _webSocket.sink.add(jsonEncode({"command": "subscribe_logs"}));
      _webSocket.sink.add(jsonEncode({"command": "subscribe_statustext"}));

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
    String initialPositionSpeed =
        prefs.getString('initialPositionSpeed') ?? "3";
    String targetAltitude = prefs.getString('targetAltitude') ?? "1";
    String offsetDistance = prefs.getString('offsetDistance') ?? "4";
    String revolveSpeed = prefs.getString('revolveSpeed') ?? "2";
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
      "initial_position_speed":
          _parseParam(initialPositionSpeed, 3.0, 'initial_position_speed'),
      "target_altitude": _parseParam(targetAltitude, 1.0, 'target_altitude'),
      "offset_distance": _parseParam(offsetDistance, 4.0, 'offset_distance'),
      "revolve_speed": _parseParam(revolveSpeed, 2.0, 'revolve_speed'),
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

  // Send emergency force disarm command
  Future<void> sendForceDisarm() async {
    if (!isConnected) {
      if (kDebugMode) {
        print("⚠️ WebSocket is not connected.");
      }
      LogManager().addLog("⚠️ WebSocket is not connected.");
      return;
    }

    sendCommand("force_disarm", {});

    // Notify listeners that an emergency stop was triggered
    _emergencyStopStreamController.add(null);

    if (kDebugMode) {
      print("🔚 Sent Force Disarm Command");
    }
    LogManager().addLog("🔚 Sent Force Disarm Command");
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

  void registerLocalModeSelection(String mode) {
    _lastLocalModeSelection = mode;
    _lastLocalModeSelectionAt = DateTime.now();
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
  Future<void> _handleIncomingMessage(String data) async {
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
        final logMessage = message["message"]?.toString() ?? "";
        final droneId = message["drone_id"]?.toString();
        final prefixMatch =
            RegExp(r'^Drone\s+(\S+):\s*(.*)').firstMatch(logMessage);
        if (droneId != null && droneId.isNotEmpty) {
          addDroneStatus(droneId, logMessage);
        } else if (prefixMatch != null) {
          addDroneStatus(prefixMatch.group(1)!, prefixMatch.group(2)!);
        } else {
          addServerLog(logMessage);
          LogManager().addLog("📜 Server Log: $logMessage");
        }
      } else if (message["command"] == "landing_complete") {
        _landingCompleteStreamController.add(null);
        if (kDebugMode) {
          print("🛬 Landing complete signal received");
        }
        LogManager().addLog("🛬 Landing complete signal received");
      } else if (message["command"] == "drone_disconnected") {
        final droneId = message["drone_id"]?.toString() ?? "unknown";
        telemetryData.remove(droneId);
        _telemetryStreamController.add(null);
        _landingCompleteStreamController.add(null);
        final alert =
            "⚠️ Drone $droneId disconnected. Operations halted.";
        if (kDebugMode) {
          print(alert);
        }
        LogManager().addLog(alert);
      } else if (message["command"] == "statustext") {
        final droneId = message["drone_id"]?.toString() ?? "unknown";
        final text = message["message"]?.toString() ?? "";
        addDroneStatus(droneId, text);
      } else if (message["command"] == "mode_update") {
        final mode = message["data"] ?? {};
        final prefs = await SharedPreferences.getInstance();
        String selectedMode = "Normal";
        if (mode["orbit_around_user"] == true) {
          selectedMode = "Orbit";
        } else if (mode["swap_positions"] == true) {
          selectedMode = "Swap Positions";
        } else if (mode["rotate_triangle_formation"] == true) {
          selectedMode = "Rotate Triangle";
        }

        final localMode = _lastLocalModeSelection;
        final localSelectionAt = _lastLocalModeSelectionAt;
        final isWithinLocalGracePeriod = localSelectionAt != null &&
            DateTime.now().difference(localSelectionAt) <=
                _localModeSelectionGracePeriod;

        if (isWithinLocalGracePeriod &&
            localMode != null &&
            selectedMode != localMode) {
          LogManager().addLog(
              "⏳ Ignoring stale server mode_update ($selectedMode) during local mode sync.");
          return;
        }

        await prefs.setString('selectedMode', selectedMode);
        // Ensure GPS services pick up the new mode immediately
        GPSService().refreshSettings();
        SimulatedGPSService().refreshSettings();
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
      _webSocket.sink.add(jsonEncode({"command": "unsubscribe_statustext"}));
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
    _landingCompleteStreamController.close();
    _connectionStatusController.close();
    _droneStatusStreamController.close();
    _emergencyStopStreamController.close();
  }
}
