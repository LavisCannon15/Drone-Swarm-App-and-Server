import 'dart:async';
import 'package:flutter/material.dart';
import '../services/log_manager.dart';
import '../services/websocket_service.dart';

class ConsoleScreen extends StatefulWidget {
  @override
  _ConsoleScreenState createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  Duration logUpdateInterval = Duration(milliseconds: 500); // ✅ Throttle log updates every 500ms
  Timer? _logUpdateTimer;
  List<String> _flutterLogs = [];
  List<String> _serverLogs = [];
  bool isReceivingLogs = true; // ✅ Toggle for pausing/resuming logs

  @override
  void initState() {
    super.initState();

    // ✅ Set up real-time log updates
    _logUpdateTimer = Timer.periodic(logUpdateInterval, (_) {
      if (mounted && isReceivingLogs) {
        setState(() {
          _flutterLogs = List<String>.from(LogManager().logs);
          _serverLogs = List<String>.from(WebSocketService().serverLogs);
        });
      }
    });
  }

  @override
  void dispose() {
    _logUpdateTimer?.cancel(); // ✅ Stop timer when screen is closed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Console Logs"),
          actions: _buildConsoleButtons(), // ✅ Buttons in top-right corner
          bottom: TabBar(
            tabs: [
              Tab(text: "Flutter Console"),
              Tab(text: "Server Console"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFlutterConsole(),
            _buildServerConsole(),
          ],
        ),
      ),
    );
  }

  Widget _buildFlutterConsole() {
    return Container(
      color: Colors.black, // ✅ Restore black background
      child: ListView.builder(
        padding: EdgeInsets.all(10),
        itemCount: _flutterLogs.length,
        itemBuilder: (context, index) {
          // ✅ Filter out "Server Log:" entries from the Flutter Console
          if (_flutterLogs[index].contains("Server Log:")) {
            return SizedBox.shrink(); // ✅ Hide server logs in Flutter Console
          }
          return _buildLogText(_flutterLogs[index]);
        },
      ),
    );
  }

  Widget _buildServerConsole() {
    return Container(
      color: Colors.black, // ✅ Restore black background
      child: ListView.builder(
        padding: EdgeInsets.all(10),
        itemCount: _serverLogs.length,
        itemBuilder: (context, index) {
          return _buildLogText(_serverLogs[index]);
        },
      ),
    );
  }

  /// ✅ Correctly restore buttons in the **top-right corner** with **icons**
  List<Widget> _buildConsoleButtons() {
    return [
      IconButton(
        icon: Icon(LogManager().isPaused ? Icons.play_arrow : Icons.pause),
        tooltip: LogManager().isPaused ? "Resume Logs" : "Pause Logs",
        onPressed: () {
          setState(() {
            bool newPauseState = !LogManager().isPaused;
            LogManager().pauseLogging(newPauseState);
          });
        },
      ),
      IconButton(
        icon: Icon(Icons.delete),
        tooltip: "Clear Logs",
        onPressed: () {
          setState(() {
            _flutterLogs = List<String>.from(LogManager().logs);
            _serverLogs = List<String>.from(WebSocketService().serverLogs);

            LogManager().clearLogs();
            WebSocketService().serverLogs.clear();
          });

          print("🗑️ Console logs cleared.");
        },


      ),


    ];
  }

  Widget _buildLogText(String log) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Text(
        log,
        style: TextStyle(color: _getLogColor(log)),
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains("❌")) return Colors.red; // Error logs
    if (log.contains("⚠️")) return Colors.orange; // Warnings
    if (log.contains("✅") || log.contains("📜")) return Colors.green; // Success/info logs
    return Colors.white; // Default log color
  }
}
