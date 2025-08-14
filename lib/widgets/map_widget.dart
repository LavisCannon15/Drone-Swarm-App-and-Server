import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import '../services/gps_service.dart';
import '../services/websocket_service.dart';

class MapWidget extends StatefulWidget {

  const MapWidget({super.key});

  @override
  MapWidgetState createState() => MapWidgetState();
}

class MapWidgetState extends State<MapWidget> {
  GoogleMapController? _mapController;
  final GPSService gpsService = GPSService();
  final WebSocketService webSocketService = WebSocketService();

  double? latitude;
  double? longitude;
  bool isGPSReady = false;
  Set<Marker> _markers = {};
  StreamSubscription<void>? _telemetrySub;
  BitmapDescriptor? _droneIcon;
  final Map<String, LatLng> _previousPositions = {};
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeMapRenderer();
    initializeCameraPosition();
    _loadDroneIcon();
    _telemetrySub =
    webSocketService.telemetryStream.listen((_) => _scheduleMarkerUpdate());
  }

  Future<void> _loadDroneIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/drone_marker.png',
    );
    if (!mounted) return;
    setState(() => _droneIcon = icon);
    _scheduleMarkerUpdate();
  }

  Future<void> initializeCameraPosition() async {
    Map<String, dynamic>? locationData;
    try {
      locationData = await gpsService.locationStream.first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      locationData = null;
    }
    if (!mounted) return;

    if (locationData == null) {
      debugPrint('GPS fix not acquired; using fallback location.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'GPS fix not acquired; using fallback location.')),
          );
        }
      });
    }

    setState(() {
      latitude = locationData?['latitude'] ?? 37.7749;
      longitude = locationData?['longitude'] ?? -122.4194;
      isGPSReady = true; // show map regardless
    });
  }

  void _initializeMapRenderer() {
    final GoogleMapsFlutterPlatform mapsImplementation =
        GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true;
    }
  }

  void recenterOnUser() async {
    Map<String, dynamic>? locationData;
    try {
      locationData = await gpsService.locationStream.first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      locationData = null;
    }
    if (!mounted) return;
    if (_mapController != null &&
        locationData?['latitude'] != null &&
        locationData?['longitude'] != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(locationData!['latitude'], locationData['longitude']),
          18.0,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to obtain GPS fix.')),
      );
    }
  }

  void _scheduleMarkerUpdate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), _updateMarkers);
  }


  void _updateMarkers() {
    bool updated = false;
    final data = webSocketService.telemetryData;
    final currentIds = data.keys.toSet();

    final removedIds =
        _previousPositions.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in removedIds) {
      _previousPositions.remove(id);
      _markers.removeWhere((m) => m.markerId.value == id);
      updated = true;
    }

    data.forEach((id, value) {
      final location = LatLng(
        (value['latitude'] as num?)?.toDouble() ?? 0.0,
        (value['longitude'] as num?)?.toDouble() ?? 0.0,
      );
      final previous = _previousPositions[id];
      if (previous == null || previous != location) {
        _previousPositions[id] = location;
        final marker = Marker(
          markerId: MarkerId(id),
          position: location,
          icon: _droneIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        );
        _markers.removeWhere((m) => m.markerId.value == id);
        _markers.add(marker);
        updated = true;
      }
    });

    if (updated && mounted) {
      setState(() {});
    }
  }


  @override
  void dispose() {
    _telemetrySub?.cancel();
    _debounceTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isGPSReady || latitude == null || longitude == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(latitude!, longitude!),
        zoom: 18.0,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      markers: _markers,
      onMapCreated: (controller) => _mapController = controller,
      mapType: MapType.normal,
    );
  }
}
