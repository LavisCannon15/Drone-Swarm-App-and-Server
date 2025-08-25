import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/log_manager.dart';
import '../services/websocket_service.dart';
import 'package:share_plus/share_plus.dart';

class ConsoleScreen extends StatefulWidget {
const ConsoleScreen({super.key});

  @override
  _ConsoleScreenState createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {

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
      child: StreamBuilder<List<String>>(
        stream: LogManager().logStream,
        initialData: LogManager().logs,
        builder: (context, snapshot) {
          final logs = (snapshot.data ?? [])
              .where((log) => !log.contains("Server Log:"))
              .toList();
          return ListView.builder(
            padding: EdgeInsets.all(10),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              return _buildLogText(logs[index]);
            },
          );
        },
      ),
    );
  }


  Widget _buildServerConsole() {
    return Container(
      color: Colors.black, // ✅ Restore black background
      child: StreamBuilder<List<String>>(
        stream: WebSocketService().serverLogStream,
        initialData: WebSocketService().serverLogs,
        builder: (context, snapshot) {
          final logs = snapshot.data ?? [];
          return ListView.builder(
            padding: EdgeInsets.all(10),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              return _buildLogText(logs[index]);
            },
          );
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

          LogManager().clearLogs();
          WebSocketService().clearServerLogs();

          if (kDebugMode) {
            print("🗑️ Console logs cleared.");
          }
        },


      ),

      IconButton(
        icon: Icon(Icons.share),
        tooltip: "Export Logs",
        onPressed: () async {
          final logManager = LogManager();
          final file = await logManager.getLogFile();
          await file.writeAsString(logManager.logs.join('\n'));
          await Share.shareXFiles([XFile(file.path)], text: 'Application Logs');
          logManager.clearLogs();
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



