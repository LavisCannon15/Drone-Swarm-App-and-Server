import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/log_manager.dart';
import '../services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GPSService {
  static final GPSService _instance = GPSService._internal();

  factory GPSService() {
    return _instance;
  }

  GPSService._internal() {
    _initGPSService();
  }

  final StreamController<Map<String, dynamic>> locationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<Position>? gpsSubscription;
  Timer? uiUpdateTimer;

  double speed = 0.0;
  double? lastLatitude;
  double? lastLongitude;
  double? lastSpeed;

  void _initGPSService() async {
    if (!await _checkLocationServices()) return;
    if (!await _checkPermissions()) return;

    _startGPSTracking();
    _startUIUpdateTimer();
  }

  Future<bool> _checkLocationServices() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      LogManager().addLog("❌ Location services are disabled.");
      print("❌ Location services are disabled.");
      return false;
    }
    return true;
  }

  Future<bool> _checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        LogManager().addLog("❌ Location permissions are permanently denied.");
        print("❌ Location permissions are permanently denied.");
        return false;
      }
    }
    return true;
  }

  void _startGPSTracking() {
    if (gpsSubscription != null) return; // Prevent duplicate subscriptions
    gpsSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((Position position) {
      _handleNewGPSData(position);
    });
  }

  void _handleNewGPSData(Position position) {
    lastLatitude = position.latitude;
    lastLongitude = position.longitude;
    speed = position.speed;

    _updateLocationStream();
  }

  void _startUIUpdateTimer() {
    uiUpdateTimer?.cancel();
    uiUpdateTimer = Timer.periodic(Duration(milliseconds: 100), (_) {
      _updateLocationStream();
    });
  }

  void _updateLocationStream() async {
    if (lastLatitude == null || lastLongitude == null) return;
    if (lastSpeed == speed) return;  // Prevent redundant updates
    lastSpeed = speed;

    final gpsData = {
      "latitude": lastLatitude!,
      "longitude": lastLongitude!,
      "speed": speed.toStringAsFixed(2),
    };

    // Retrieve settings from SharedPreferences like simulated GPS service does
    final prefs = await SharedPreferences.getInstance();
    double offsetDistance = double.tryParse(prefs.getString('offsetDistance') ?? '') ?? 4.0;
    double revolveSpeed = double.tryParse(prefs.getString('revolveSpeed') ?? '') ?? 3.0;
    double revolveOffsetDistance = double.tryParse(prefs.getString('revolveOffsetDistance') ?? '') ?? 4.0;
    double swapPositionSpeed = double.tryParse(prefs.getString('swapPositionSpeed') ?? "1") ?? 1.0;
    String selectedMode = prefs.getString('selectedMode') ?? "Normal";

    // Send GPS data via WebSocket if connected
    final webSocketService = WebSocketService();
    if (webSocketService.isConnected) {
      webSocketService.sendUserGPSData(
        latitude: lastLatitude!,
        longitude: lastLongitude!,
        speed: speed,
        offsetDistance: offsetDistance,
        revolveSpeed: revolveSpeed,
        revolveOffsetDistance: revolveOffsetDistance,
        swapPositionSpeed: swapPositionSpeed,
        selectedMode: selectedMode,
      );
    }

    locationStreamController.add(gpsData);

    print("📡 Location Stream Updated: Lat=${lastLatitude!}, Lng=${lastLongitude!}, Speed=$speed");
  }


  Stream<Map<String, dynamic>> get locationStream => locationStreamController.stream;

  void dispose() {
    gpsSubscription?.cancel();
    uiUpdateTimer?.cancel();
    locationStreamController.close();
  }
}
