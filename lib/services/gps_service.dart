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

  // Cached SharedPreferences values
  double _offsetDistance = 4.0;
  double _revolveSpeed = 3.0;
  double _revolveOffsetDistance = 4.0;
  double _swapPositionSpeed = 1.0;
  String _selectedMode = "Normal";

  Future<void> _initGPSService() async {
    await _loadPreferences();
    if (!await _checkLocationServices()) return;
    if (!await _checkPermissions()) return;

    _startGPSTracking();
    _startUIUpdateTimer();
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
    _selectedMode = prefs.getString('selectedMode') ?? "Normal";
  }

  Future<void> refreshSettings() async => _loadPreferences();

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

  void _updateLocationStream() {
    if (lastLatitude == null || lastLongitude == null) return;
    if (lastSpeed == speed) return; // Prevent redundant updates
    lastSpeed = speed;

    final gpsData = {
      "latitude": lastLatitude!,
      "longitude": lastLongitude!,
      "speed": speed.toStringAsFixed(2),
    };

    final webSocketService = WebSocketService();
    if (webSocketService.isConnected) {
      webSocketService.sendUserGPSData(
        latitude: lastLatitude!,
        longitude: lastLongitude!,
        speed: speed,
        offsetDistance: _offsetDistance,
        revolveSpeed: _revolveSpeed,
        revolveOffsetDistance: _revolveOffsetDistance,
        swapPositionSpeed: _swapPositionSpeed,
        selectedMode: _selectedMode,
      );
    }

    locationStreamController.add(gpsData);
    print(
        "📡 Location Stream Updated: Lat=${lastLatitude!}, Lng=${lastLongitude!}, Speed=$speed");
  }

  Stream<Map<String, dynamic>> get locationStream =>
      locationStreamController.stream;

  void dispose() {
    gpsSubscription?.cancel();
    uiUpdateTimer?.cancel();
    locationStreamController.close();
  }
}
