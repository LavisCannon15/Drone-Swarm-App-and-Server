import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';

/// Generates deterministic GPS positions for desktop/CI usage.
class SimulatedGPSService {
  // ----- Singleton -----------------------------------------------------------
  static final SimulatedGPSService _instance = SimulatedGPSService._internal();
  factory SimulatedGPSService() => _instance;
  SimulatedGPSService._internal();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _init();
  }

  double latitude = -35.3631723;
  double longitude = 149.1652375;
  double speed = 1.0;                  // meters per second
  double maxDistance = 20.0;           // meters

  bool isStationary = true;

  double _distanceTraveled = 0.0;
  int _direction = 1;                  // 1 = north, -1 = south
  static const double METERS_PER_DEGREE_LAT = 111139.0;

  final WebSocketService _ws = WebSocketService();
  final _locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  Timer? _timer;

  // Cached settings
  double _offsetDistance = 4.0;
  double _revolveSpeed = 2.0;
  double _revolveOffsetDistance = 4.0;
  double _swapPositionSpeed = 1.0;
  String _selectedMode = 'Normal';

  // ----- Initialisation -----------------------------------------------------
  Future<void> _init() async {
    await _loadPreferences();
    _start();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    speed = double.tryParse(prefs.getString('simSpeed') ?? '') ?? 1.0;
    maxDistance =
        double.tryParse(prefs.getString('simMaxDistance') ?? '') ?? 20.0;
    _offsetDistance =
        double.tryParse(prefs.getString('offsetDistance') ?? '') ?? 4.0;
    _revolveSpeed =
        double.tryParse(prefs.getString('revolveSpeed') ?? '') ?? 2.0;
    _revolveOffsetDistance =
        double.tryParse(prefs.getString('revolveOffsetDistance') ?? '') ?? 4.0;
    _swapPositionSpeed =
        double.tryParse(prefs.getString('swapPositionSpeed') ?? '') ?? 1.0;
    _selectedMode = prefs.getString('selectedMode') ?? 'Normal';
  }

  /// Reload preferences after they change.
  Future<void> refreshSettings() => _loadPreferences();

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isStationary) {
        final deltaLat = (_direction * speed) / METERS_PER_DEGREE_LAT;
        latitude += deltaLat;
        _distanceTraveled += speed;
        if (_distanceTraveled >= maxDistance) {
          _direction *= -1;
          _distanceTraveled = 0.0;
        }
      }

      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'speed': isStationary ? 0.0 : speed,   // always ≥ 0
        'direction': _direction,
        'offset_distance': _offsetDistance,
        'revolve_speed': _revolveSpeed,
        'revolve_offset_distance': _revolveOffsetDistance,
        'swap_position_speed': _swapPositionSpeed,
        'selectedMode': _selectedMode,
      };

      _locationStreamController.add(locationData);

      _ws.sendUserGPSData(
        latitude: latitude,
        longitude: longitude,
        speed: locationData['speed'] as double,
        offsetDistance: _offsetDistance,
        revolveSpeed: _revolveSpeed,
        revolveOffsetDistance: _revolveOffsetDistance,
        swapPositionSpeed: _swapPositionSpeed,
        selectedMode: _selectedMode,
      );
    });
  }

  void setStationary(bool value) => isStationary = value;

  void dispose() {
    _timer?.cancel();
    _locationStreamController.close();
    _initialized = false;
  }
}
