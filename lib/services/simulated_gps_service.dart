
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
import '../services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SimulatedGPSService {
  double latitude = -35.3631723;      // Starting point
  double longitude = 149.1652375;
  double speed = 1.0;                 // meters per second
  final double maxDistance = 20.0;     // total travel range

  bool isStationary = false;           // toggle to pause movement

  double _distanceTraveled = 0.0;
  int _direction = 1;                 // 1 = forward, -1 = backward

  static const double METERS_PER_DEGREE_LAT = 111139.0;

  final WebSocketService _webSocketService = WebSocketService();
  final StreamController<Map<String, dynamic>> _locationStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get locationStream =>
      _locationStreamController.stream;

  Timer? _timer;

  SimulatedGPSService() {
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isStationary) {
        final double deltaLat = (_direction * speed) / METERS_PER_DEGREE_LAT;
        latitude += deltaLat;
        _distanceTraveled += speed;

        if (_distanceTraveled >= maxDistance) {
          _direction *= -1;
          _distanceTraveled = 0.0;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final double offsetDistance =
          double.tryParse(prefs.getString('offsetDistance') ?? '') ?? 4.0;
      final double revolveSpeed =
          double.tryParse(prefs.getString('revolveSpeed') ?? '') ?? 3.0;
      final double revolveOffsetDistance =
          double.tryParse(prefs.getString('revolveOffsetDistance') ?? '') ?? 4.0;
      final double swapPositionSpeed =
          double.tryParse(prefs.getString('swapPositionSpeed') ?? '') ?? 1.0;
      final String selectedMode = prefs.getString('selectedMode') ?? 'Normal';

      final locationData = {
        "latitude": latitude,
        "longitude": longitude,
        "speed": isStationary ? 0.0 : speed * _direction,
        "offset_distance": offsetDistance,
        "revolve_speed": revolveSpeed,
        "revolve_offset_distance": revolveOffsetDistance,
        "swap_position_speed": swapPositionSpeed,
        "selectedMode": selectedMode,
      };

      _locationStreamController.add(locationData);

      _webSocketService.sendUserGPSData(
        latitude: latitude,
        longitude: longitude,
        speed: locationData["speed"] as double,
        offsetDistance: offsetDistance,
        revolveSpeed: revolveSpeed,
        revolveOffsetDistance: revolveOffsetDistance,
        swapPositionSpeed: swapPositionSpeed,
        selectedMode: selectedMode,
      );
    });
  }

  void setStationary(bool stationary) {
    isStationary = stationary;
  }

  void dispose() {
    _timer?.cancel();
    _locationStreamController.close();
  }
}
