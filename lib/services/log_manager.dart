import 'dart:async';

class LogManager {
  static final LogManager _instance = LogManager._internal();
  final List<String> _logs = [];
  final StreamController<List<String>> _logStreamController =
      StreamController.broadcast();
  bool _isPaused = false;
  static const int _maxLogs = 500;

  factory LogManager() {
    return _instance;
  }

  LogManager._internal();

  void addLog(String message) {
    if (_isPaused) return;

    final logEntry = "[${DateTime.now().toLocal()}] $message";
    _logs.add(logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    _logStreamController.add(List.from(_logs));
  }

  void pauseLogging(bool shouldPause) {
    _isPaused = shouldPause;
  }

  bool get isPaused => _isPaused;

  List<String> get logs => List.unmodifiable(_logs);

  Stream<List<String>> get logStream => _logStreamController.stream;

  void clearLogs() {
    _logs.clear();
    _logStreamController.add([]);
  }
}
