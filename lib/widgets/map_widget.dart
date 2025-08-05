import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:collection/collection.dart';
import '../services/gps_service.dart';
import '../services/websocket_service.dart';

class MapWidget extends StatefulWidget {
  final GlobalKey<MapWidgetState> key;

  MapWidget({required this.key}) : super(key: key);

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
  Timer? _telemetryTimer;
  BitmapDescriptor? _droneIcon;

  @override
  void initState() {
    super.initState();
    _initializeMapRenderer();
    initializeCameraPosition();
    _loadDroneIcon();
    startDroneTelemetryUpdates();
  }

  Future<void> _loadDroneIcon() async {
    _droneIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/drone_marker.png',
    );
  }

  void startDroneTelemetryUpdates() {
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateMarkers();
    });
  }

  void initializeCameraPosition() async {
    final locationData = await gpsService.locationStream.first;
    setState(() {
      latitude = locationData['latitude'];
      longitude = locationData['longitude'];
      isGPSReady = true;
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
    final locationData = await gpsService.locationStream.first;
    if (_mapController != null &&
        locationData['latitude'] != null &&
        locationData['longitude'] != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(locationData['latitude'], locationData['longitude']),
          18.0,
        ),
      );
    }
  }

  void _updateMarkers() {
    Set<Marker> markers = {};
    final droneLocations = webSocketService.telemetryData.map(
      (id, data) => MapEntry(
        id,
        LatLng(
          (data['latitude'] as num?)?.toDouble() ?? 0.0,
          (data['longitude'] as num?)?.toDouble() ?? 0.0,
        ),
      ),
    );

    droneLocations.forEach((id, location) {
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: location,
          icon: _droneIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });

    if (!const SetEquality().equals(_markers, markers)) {
      setState(() => _markers = markers);
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isGPSReady) {
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
