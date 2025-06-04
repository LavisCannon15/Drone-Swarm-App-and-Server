import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'services/log_manager.dart';
import 'screens/shared_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Global error handler for Flutter framework errors (No Stack Trace in LogManager)
  FlutterError.onError = (FlutterErrorDetails details) {
    String errorMessage = "❌ FLUTTER ERROR: ${details.exceptionAsString()}";
    LogManager().addLog(errorMessage); // ✅ Logs error without stack trace
    debugPrint("$errorMessage\nStack Trace:\n${details.stack.toString()}"); // ✅ Prints full stack trace in terminal
    FlutterError.presentError(details);
  };

  // ✅ Global error handler for all unhandled Dart async errors (No Stack Trace in LogManager)
  runZonedGuarded(() async {
    // Initialize LogManager
    LogManager();
    LogManager().addLog("🚀 LogManager initialized!");

    try {
      // ✅ Initialize the FMTC backend
      await FMTCObjectBoxBackend().initialise();
      LogManager().addLog("🗺️ Tile caching backend initialized successfully!");

      // ✅ Create and manage the FMTC Store using StoreManagement
      final store = FMTCStore('carto_cache');

      // Check if the store is ready (exists), if not, create it
      bool storeExists = await store.manage.ready;
      if (!storeExists) {
        await store.manage.create();
        LogManager().addLog("📦 FMTC Store 'carto_cache' created successfully!");
      } else {
        LogManager().addLog("🔄 FMTC Store 'carto_cache' already exists.");
      }
    } catch (error, stackTrace) {
      String errorMessage = "❌ TILE CACHING ERROR: $error";
      LogManager().addLog(errorMessage); // ✅ Logs error without stack trace
      debugPrint("$errorMessage\nStack Trace:\n$stackTrace"); // ✅ Prints full stack trace in terminal
    }

    runApp(MyApp());
  }, (error, stackTrace) {
    String errorMessage = "❌ UNHANDLED ERROR: $error";
    LogManager().addLog(errorMessage); // ✅ Logs error without stack trace
    debugPrint("$errorMessage\nStack Trace:\n$stackTrace"); // ✅ Prints full stack trace in terminal
  });
}



class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drone Swarm UI',
      home: SharedHome(),
    );
  }
}
