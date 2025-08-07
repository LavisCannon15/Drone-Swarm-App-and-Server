import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class ConnectButton extends StatefulWidget {
  @override
  _ConnectButtonState createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton> {
  final WebSocketService webSocketService = WebSocketService();
  String connectionStatus = "Not Connected";
  List<String> droneConnections = [];
  Timer? _connectionMonitorTimer;

  @override
  void initState() {
    super.initState();
    _loadDroneConnections();
    _monitorWebSocketConnection();
  }

  void _monitorWebSocketConnection() {
    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        final newStatus = webSocketService.isConnected ? "Connected via WebSocket" : "Not Connected";
        if (newStatus != connectionStatus) {
          setState(() => connectionStatus = newStatus);
        }
      }
    });
  }

  Future<void> _loadDroneConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDrones = prefs.getStringList('drones') ?? [];
    if (kDebugMode) print("📥 Loaded drone connections: $savedDrones");
    LogManager().addLog("📥 Loaded drone connections: $savedDrones");

    if (!mounted) return;
    setState(() {
      final connections = <String>[];
      for (final droneData in savedDrones) {
        final parts = droneData.split(';');
        if (parts.length >= 2) {
          connections.add(parts[1]);
        } else {
          if (kDebugMode) print("⚠️ Invalid drone entry: $droneData");
          LogManager().addLog("⚠️ Invalid drone entry: $droneData");
        }
      }
      droneConnections = connections;
    });
  }

  Future<void> _connectToDrones() async {
    setState(() => connectionStatus = "Connecting...");

    if (kDebugMode) print("🔗 Attempting to connect...");
    LogManager().addLog("🔗 Attempting to connect...");

    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('serverAddress') ?? '';
    if (serverUrl.isEmpty) {
      if (!mounted) return;
      setState(() => connectionStatus = "Server not configured");
      return;
    }

    if (!mounted) return;
    setState(() => connectionStatus = "Connecting to $serverUrl");

    try {
      if (!webSocketService.isConnected) {
        await webSocketService.connect(serverUrl);
      }
      await webSocketService.connectToDrones(droneConnections);

      if (webSocketService.isConnected) {
        if (!mounted) return;
        setState(() => connectionStatus = "Connected via WebSocket");
        LogManager().addLog("📡 Drone connections sent: $droneConnections");
      } else {
        if (!mounted) return;
        setState(() => connectionStatus = "WebSocket Connection Failed");
      }
    } catch (e) {
      LogManager().addLog("❌ Connection failed: $e");
      if (!mounted) return;
      setState(() => connectionStatus = "Connection Failed");
    }
  }

  @override
  void dispose() {
    _connectionMonitorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _connectToDrones,
      child: Text(connectionStatus),
    );
  }
}