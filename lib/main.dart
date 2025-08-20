import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'services/log_manager.dart';
import 'services/gps_service.dart';
import 'services/simulated_gps_service.dart';
import 'screens/shared_home.dart';

void main() {
  // ✅ Global error handler for all unhandled Dart async errors (No Stack Trace in LogManager)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ Global error handler for Flutter framework errors (No Stack Trace in LogManager)
    FlutterError.onError = (FlutterErrorDetails details) {
      String errorMessage = "❌ FLUTTER ERROR: ${details.exceptionAsString()}";
      LogManager().addLog(errorMessage); // ✅ Logs error without stack trace
      debugPrint("$errorMessage\nStack Trace:\n${details.stack.toString()}"); // ✅ Prints full stack trace in terminal
      FlutterError.presentError(details);
    };

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

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await GPSService().init();
    } else {
      await SimulatedGPSService().init();
    }

    runApp(const MyApp());
  }, (error, stackTrace) {
    String errorMessage = "❌ UNHANDLED ERROR: $error";
    LogManager().addLog(errorMessage); // ✅ Logs error without stack trace
    debugPrint("$errorMessage\nStack Trace:\n$stackTrace"); // ✅ Prints full stack trace in terminal
  });
}



class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drone Swarm UI',
      home: const SharedHome(),
    );
  }
}
