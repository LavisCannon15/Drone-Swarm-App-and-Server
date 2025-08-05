import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_manager.dart';
import '../services/websocket_service.dart';

/// Singleton service that streams the user’s GPS position to the WebSocket
/// server and to listeners inside the Flutter app.
class GPSService {
  static final GPSService _instance = GPSService._internal();
  factory GPSService() => _instance;
  GPSService._internal() {
    _initGPSService(); // fire‑and‑forget init
  }

  /* ---------------------------------------------------------------------------
   *  Public stream for widgets / other services
   * ------------------------------------------------------------------------ */
  final _locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  /* ---------------------------------------------------------------------------
   *  Internal state
   * ------------------------------------------------------------------------ */
  StreamSubscription<Position>? _gpsSubscription;

  double? _latitude;
  double? _longitude;
  double _speed = 0.0;

  // Cached preference values (loaded once, refreshed on demand)
  double _offsetDistance = 4.0;
  double _revolveSpeed = 3.0;
  double _revolveOffsetDistance = 4.0;
  double _swapPositionSpeed = 1.0;
  String _selectedMode = 'Normal';

  /* ---------------------------------------------------------------------------
   *  Initialisation
   * ------------------------------------------------------------------------ */
  Future<void> _initGPSService() async {
    await _loadPreferences();

    if (!await _checkLocationServices()) return;
    if (!await _checkPermissions()) return;

    _startGPSTracking(); // begin streaming real GPS data
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

  /// Call when preferences change to update the cached values.
  Future<void> refreshSettings() async => _loadPreferences();

  /* ---------------------------------------------------------------------------
   *  Permissions / service checks
   * ------------------------------------------------------------------------ */
  Future<bool> _checkLocationServices() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      LogManager().addLog('❌ Location services are disabled.');
    }
    return enabled;
  }

  Future<bool> _checkPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        LogManager().addLog('❌ Location permissions are denied.');
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        LogManager().addLog('❌ Location permissions are permanently denied.');
        return false;
      }
    } else if (permission == LocationPermission.deniedForever) {
      LogManager().addLog('❌ Location permissions are permanently denied.');
      return false;
    }
    return true;
  }

  /* ---------------------------------------------------------------------------
   *  GPS tracking
   * ------------------------------------------------------------------------ */
  void _startGPSTracking() {
    if (_gpsSubscription != null) return; // already running
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      _handleNewGPSData,
      onError: (error) {
        LogManager().addLog('❌ GPS stream error: $error');
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

  void _handleNewGPSData(Position position) {
    _latitude = position.latitude;
    _longitude = position.longitude;
    _speed = position.speed;

    _pushLocationUpdate();
  }

  /* ---------------------------------------------------------------------------
   *  Emit to WebSocket + app listeners
   * ------------------------------------------------------------------------ */
  void _pushLocationUpdate() {
    if (_latitude == null || _longitude == null) return;

    final data = {
      'latitude': _latitude!,
      'longitude': _longitude!,
      'speed': _speed.toStringAsFixed(2),
    };

    // Send to Python server if connected
    final ws = WebSocketService();
    if (ws.isConnected) {
      ws.sendUserGPSData(
        latitude: _latitude!,
        longitude: _longitude!,
        speed: _speed,
        offsetDistance: _offsetDistance,
        revolveSpeed: _revolveSpeed,
        revolveOffsetDistance: _revolveOffsetDistance,
        swapPositionSpeed: _swapPositionSpeed,
        selectedMode: _selectedMode,
      );
    }

    _locationStreamController.add(data); // emit to Flutter listeners
  }

  /* ---------------------------------------------------------------------------
   *  Cleanup
   * ------------------------------------------------------------------------ */
  void dispose() {
    _gpsSubscription?.cancel();
    _locationStreamController.close();
  }
}
