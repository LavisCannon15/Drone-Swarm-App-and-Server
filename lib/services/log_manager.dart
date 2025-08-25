import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LogManager {
  static final LogManager _instance = LogManager._internal();
  final List<String> _logs = [];
  File? _logFile;
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

  /// Returns the log file containing persisted log entries.
  Future<File> getLogFile() async {
    return await _getLogFile();
  }

  void clearLogs() {
    _logs.clear();
    _logStreamController.add([]);
  }

  void dispose() {
    _logStreamController.close();
  }

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/app_logs.txt');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _logFile = file;
    return file;
  }

}
