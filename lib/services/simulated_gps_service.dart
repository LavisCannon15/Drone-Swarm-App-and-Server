
/**
class SimulatedGPSService {
  double latitude = -35.3631723; // Initial latitude
  double longitude = 149.1652367; // Initial longitude
  double speed = 5.0; // Simulated speed in m/s

  Map<String, dynamic> getSimulatedUserLocationAndSpeed() {
    // Simulate small changes in location for testing
    latitude += 0.0001;
    longitude += 0.0001;
    speed += 0.1;

    return {
      "latitude": latitude.toStringAsFixed(4),
      "longitude": longitude.toStringAsFixed(4),
      "speed": speed.toStringAsFixed(2),
    };
  }
}
*/


import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';

class SimulatedGPSService {
  double latitude = -35.3631723;
  double longitude = 149.1652375;
  double speed = 1.0;                  // meters per second
  final double maxDistance = 20.0;     // total travel range

  bool isStationary = false;

  double _distanceTraveled = 0.0;
  int _direction = 1;                  // 1 = north, -1 = south
  static const double METERS_PER_DEGREE_LAT = 111139.0;

  final WebSocketService _webSocketService = WebSocketService();
  final StreamController<Map<String, dynamic>> _locationStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  Timer? _timer;

  // Cached settings
  double _offsetDistance = 4.0;
  double _revolveSpeed = 3.0;
  double _revolveOffsetDistance = 4.0;
  double _swapPositionSpeed = 1.0;
  String _selectedMode = 'Normal';

  SimulatedGPSService() {
    _init();                     // ensures settings load before broadcasting
  }

  Future<void> _init() async {
    await _loadPreferences();
    _start();
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

  /// Allow callers to refresh cached preferences and await completion.
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
        'speed': isStationary ? 0.0 : speed, // always non‑negative
        'direction': _direction,
        'offset_distance': _offsetDistance,
        'revolve_speed': _revolveSpeed,
        'revolve_offset_distance': _revolveOffsetDistance,
        'swap_position_speed': _swapPositionSpeed,
        'selectedMode': _selectedMode,
      };

      _locationStreamController.add(locationData);

      _webSocketService.sendUserGPSData(
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

  void setStationary(bool stationary) => isStationary = stationary;

  void dispose() {
    _timer?.cancel();
    _locationStreamController.close();
  }
}
