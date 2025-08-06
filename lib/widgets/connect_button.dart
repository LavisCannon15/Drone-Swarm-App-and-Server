import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
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
    _connectionMonitorTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted) {
        String newStatus =
            webSocketService.isConnected ? "Connected via WebSocket" : "Not Connected";
        if (newStatus != connectionStatus) {
          setState(() {
            connectionStatus = newStatus;
          });
        }
      }
    });
  }

  Future<void> _loadDroneConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDrones = prefs.getStringList('drones') ?? [];
    print("📥 Loaded drone connections: $savedDrones");
    LogManager().addLog("📥 Loaded drone connections: $savedDrones");

    if (!mounted) return;
    setState(() {
      final connections = <String>[];
      for (final droneData in savedDrones) {
        final parts = droneData.split(';');
        if (parts.length >= 2) {
          connections.add(parts[1]);
        } else {
          print("⚠️ Invalid drone entry: $droneData");
          LogManager().addLog("⚠️ Invalid drone entry: $droneData");
        }
      }
      droneConnections = connections;
    });
  }

  /// Sends a UDP broadcast and waits up to [timeout] for a SERVER_RESPONSE:<ip>
  Future<String?> discoverServer({Duration timeout = const Duration(seconds: 5)}) async {
    const int DISCOVERY_PORT = 5000;
    const String DISCOVERY_MSG = 'DISCOVER_SERVER_REQUEST';

    final RawDatagramSocket socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    // send discovery packet
    socket.send(
      utf8.encode(DISCOVERY_MSG),
      InternetAddress('255.255.255.255'),
      DISCOVERY_PORT,
    );

    final completer = Completer<String?>();
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) {
          final resp = utf8.decode(dg.data);
          if (resp.startsWith('SERVER_RESPONSE:')) {
            final ip = resp.substring('SERVER_RESPONSE:'.length).trim();
            completer.complete(ip);
            socket.close();
          }
        }
      }
    });

    return completer.future.timeout(timeout, onTimeout: () {
      socket.close();
      return null;
    });
  }

  Future<void> _connectToDrones() async {
    setState(() {
      connectionStatus = "Connecting...";
    });

    print("🔗 Attempting to connect...");
    LogManager().addLog("🔗 Attempting to connect...");

    if (Platform.isAndroid) {
      // 1️⃣ Try UDP discovery first
      setState(() => connectionStatus = "Discovering server…");
      final ip = await discoverServer();

      String serverUrl;
      if (ip != null) {
        serverUrl = 'ws://$ip:5000';
      } else {
        final prefs = await SharedPreferences.getInstance();
        final manual = prefs.getString('serverAddress') ?? '';
        if (manual.isEmpty) {
          if (!mounted) return;
          setState(() => connectionStatus = "Server not found");
          return;
        }
        serverUrl = manual;
        if (!mounted) return;
        setState(() => connectionStatus = "Using manual URL");
        LogManager().addLog("🔗 Fallback to manual URL: $serverUrl");
      }

      // 3️⃣ Connect over WebSocket
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
    } else {
      // Non-Android fallback
      try {
        if (!webSocketService.isConnected) {
          await webSocketService.connect("ws://127.0.0.1:5000");
        }
        await webSocketService.connectToDrones(droneConnections);

        if (webSocketService.isConnected) {
          if (!mounted) return;
          setState(() {
            connectionStatus = "Connected via WebSocket";
          });
          print("📡 WebSocket Drone Connections Sent: $droneConnections");
          LogManager()
              .addLog("📡 WebSocket Drone Connections Sent: $droneConnections");
        } else {
          if (!mounted) return;
          setState(() {
            connectionStatus = "WebSocket Connection Failed";
          });
        }
      } catch (e) {
        print("❌ WebSocket connection failed: $e");
        LogManager().addLog("❌ WebSocket connection failed: $e");
        if (!mounted) return;
        setState(() {
          connectionStatus = "WebSocket Connection Failed";
        });
      }
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
