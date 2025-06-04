
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
import 'dart:math';
import '../services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SimulatedGPSService {
  double latitude = -35.3631723; // Initial latitude
  double longitude = 149.1652375; // Initial longitude
  double speed = 1.4; // Default walking speed in meters per second
  bool movingForward = true; // Toggle for forward/backward movement
  bool isStationary = true; // If true, user doesn't move

  static const double METERS_PER_DEGREE_LAT = 111139.0; // Conversion factor
  final WebSocketService _webSocketService = WebSocketService(); // ✅ WebSocket instance

  StreamController<Map<String, dynamic>> _locationStreamController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get locationStream => _locationStreamController.stream;

  SimulatedGPSService() {
    _startSimulatedMovement();
  }

void _startSimulatedMovement() {
  Timer.periodic(Duration(seconds: 1), (timer) async {
    if (!isStationary) {
      double movement = speed / METERS_PER_DEGREE_LAT; // Convert meters/sec to degrees
      latitude += movingForward ? movement : -movement;

      // Toggle direction randomly
      if (Random().nextInt(10) == 0) {
        movingForward = !movingForward;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    
    // ✅ Ensure conversion from String? to double with fallback values
    double offsetDistance = double.tryParse(prefs.getString('offsetDistance') ?? '') ?? 4.0;
    double revolveSpeed = double.tryParse(prefs.getString('revolveSpeed') ?? '') ?? 3.0;
    double revolveOffsetDistance = double.tryParse(prefs.getString('revolveOffsetDistance') ?? '') ?? 4.0;
    double swapPositionSpeed = double.parse(prefs.getString('swapPositionSpeed') ?? "1");  // ✅ Get Swap Position Speed
    String selectedMode = prefs.getString('selectedMode') ?? "Normal";
  

    final locationData = {
      "latitude": latitude,
      "longitude": longitude,
      "speed": isStationary ? 0.0 : speed,
      "offset_distance": offsetDistance,
      "revolve_speed": revolveSpeed,
      "revolve_offset_distance": revolveOffsetDistance,
      "swap_position_speed" : swapPositionSpeed,
      "selectedMode": selectedMode,
    };

    _locationStreamController.add(locationData); // Notify listeners

    // ✅ Send data to the WebSocket server
    _webSocketService.sendUserGPSData(
      latitude: locationData["latitude"] as double,
      longitude: locationData["longitude"] as double,
      speed: locationData["speed"] as double,
      offsetDistance: locationData["offset_distance"] as double,
      revolveSpeed: locationData["revolve_speed"] as double,
      revolveOffsetDistance: locationData["revolve_offset_distance"] as double,
      swapPositionSpeed: locationData["swap_position_speed"] as double,
      selectedMode: locationData["selectedMode"] as String,
    );
  });
}


  // Function to change speed (0 m/s means stationary)
  void setSpeed(double newSpeed) {
    speed = newSpeed;
    isStationary = (speed == 0);
  }
}
