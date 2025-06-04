import 'dart:async';

class LogManager {
  static final LogManager _instance = LogManager._internal();
  final List<String> _logs = [];
  final StreamController<List<String>> _logStreamController = StreamController.broadcast();
  bool _isPaused = false; // ✅ Now persists across screens

  factory LogManager() {
    return _instance;
  }

  LogManager._internal();

  void addLog(String message) {
    if (_isPaused) return; // ✅ Don't log if paused

    final logEntry = "[${DateTime.now().toLocal()}] $message";
    _logs.add(logEntry);
    _logStreamController.add(List.from(_logs)); // Notify UI update
  }

  void pauseLogging(bool shouldPause) {
    _isPaused = shouldPause;
  }

  bool get isPaused => _isPaused; // ✅ Now accessible in `console_screen.dart`

  List<String> get logs => List.unmodifiable(_logs);

  Stream<List<String>> get logStream => _logStreamController.stream;

  void clearLogs() {
    _logs.clear();
    _logStreamController.add([]);
  }
}
