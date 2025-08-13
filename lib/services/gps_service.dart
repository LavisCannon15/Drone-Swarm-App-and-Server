import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_manager.dart';
import '../services/websocket_service.dart';

/// Streams the real GPS position to the WebSocket server and to listeners
/// inside the Flutter app.
class GPSService {
  // ----- Singleton -----------------------------------------------------------
  static final GPSService _instance = GPSService._internal();
  factory GPSService() => _instance;
  GPSService._internal();

  Future<void> init() => _init();

  // ----- Public stream ------------------------------------------------------
  final _locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  // ----- Internal state -----------------------------------------------------
  StreamSubscription<Position>? _gpsSubscription;
  double? _lat;
  double? _lng;
  double _speed = 0.0;

  // Cached preferences
  double _offsetDistance = 4.0;
  double _revolveSpeed = 3.0;
  double _revolveOffsetDistance = 4.0;
  double _swapPositionSpeed = 1.0;
  String _selectedMode = 'Normal';

  // ----- Initialisation -----------------------------------------------------
  Future<void> _init() async {
    await _loadPreferences();
    if (!await _checkLocationServices()) return;
    if (!await _checkPermissions()) return;
    _startGPSTracking();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _offsetDistance =
        double.tryParse(prefs.getString('offsetDistance') ?? '') ?? 4.0;
    _revolveSpeed =
        double.tryParse(prefs.getString('revolveSpeed') ?? '') ?? 3.0;
    _revolveOffsetDistance =
        double.tryParse(prefs.getString('revolveOffsetDistance') ?? '') ?? 4.0;
    _swapPositionSpeed =
        double.tryParse(prefs.getString('swapPositionSpeed') ?? '') ?? 1.0;
    _selectedMode = prefs.getString('selectedMode') ?? 'Normal';
  }

  /// Call after preferences change so new values take effect immediately.
  Future<void> refreshSettings() => _loadPreferences();

  // ----- Permissions / services --------------------------------------------
  Future<bool> _checkLocationServices() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) LogManager().addLog('❌ Location services are disabled.');
    return enabled;
  }

  Future<bool> _checkPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      LogManager().addLog('❌ Location permissions are denied.');
      return false;
    }
    return true;
  }

  // ----- GPS tracking -------------------------------------------------------
  void _startGPSTracking() {
    if (_gpsSubscription != null) return; // already running
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(
      _handlePosition,
      onError: (e) {
        LogManager().addLog('❌ GPS stream error: $e');
        _gpsSubscription = null;
        Future.delayed(const Duration(seconds: 1), _startGPSTracking);
      },
      onDone: () {
        LogManager().addLog('ℹ️ GPS stream closed.');
        _gpsSubscription = null;
        Future.delayed(const Duration(seconds: 1), _startGPSTracking);
      },
      cancelOnError: true,
    );
  }

  void _handlePosition(Position pos) {
    _lat = pos.latitude;
    _lng = pos.longitude;
    _speed = pos.speed;
    _pushUpdate();
  }

  // ----- Emit to WebSocket + app listeners ---------------------------------
  void _pushUpdate() {
    if (_lat == null || _lng == null) return;

    final data = {
      'latitude': _lat!,
      'longitude': _lng!,
      'speed': _speed.toStringAsFixed(2),
    };

    final ws = WebSocketService();
    if (ws.isConnected) {
      ws.sendUserGPSData(
        latitude: _lat!,
        longitude: _lng!,
        speed: _speed,
        offsetDistance: _offsetDistance,
        revolveSpeed: _revolveSpeed,
        revolveOffsetDistance: _revolveOffsetDistance,
        swapPositionSpeed: _swapPositionSpeed,
        selectedMode: _selectedMode,
      );
    }

    _locationStreamController.add(data);
  }

  // ----- Cleanup ------------------------------------------------------------
  void dispose() {
    _gpsSubscription?.cancel();
    _locationStreamController.close();
  }
}
