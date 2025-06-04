import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:collection/collection.dart';
import '../services/gps_service.dart';

class MapWidget extends StatefulWidget {
  final GlobalKey<MapWidgetState> key; // ✅ Allows RecenterButton to access this widget

  MapWidget({required this.key}) : super(key: key);

  @override
  MapWidgetState createState() => MapWidgetState();
}

class MapWidgetState extends State<MapWidget> {
  GoogleMapController? _mapController;
  final GPSService gpsService = GPSService();

  double? latitude;
  double? longitude;
  bool isGPSReady = false;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initializeMapRenderer();
    initializeCameraPosition();
    _updateMarkers();
  }

  /// ✅ Fetch initial GPS coordinates ONCE before rendering GoogleMap
  void initializeCameraPosition() async {
    final locationData = await gpsService.locationStream.first;
    setState(() {
      latitude = locationData["latitude"];
      longitude = locationData["longitude"];
      isGPSReady = true;
    });

    print("📍 GPS Initialized: Lat=$latitude, Lng=$longitude");
  }

  void _initializeMapRenderer() {
    final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true; // ✅ Fix for updateAcquireFence issue
    }
  }

  /// ✅ Ensure Recenter Button Always Uses the Latest GPS Data
  void recenterOnUser() async {
    final locationData = await gpsService.locationStream.first; // ✅ Fetch latest GPS location

    if (_mapController != null && locationData["latitude"] != null && locationData["longitude"] != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(locationData["latitude"], locationData["longitude"]), // ✅ Use latest GPS values
          18.0,
        ),
      );
      print("📍 Map Recentered to: Lat=${locationData["latitude"]}, Lng=${locationData["longitude"]}");
    } else {
      print("❌ Error: Unable to fetch live GPS location for recentering.");
    }
  }

  void _updateMarkers() {
    Set<Marker> markers = {};

    final droneLocations = {
      "Drone 1": LatLng(0.001, 0.001),
      "Drone 2": LatLng(-0.001, -0.001),
    };

    droneLocations.forEach((id, location) {
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: LatLng(location.latitude, location.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });

    if (!const SetEquality().equals(_markers, markers)) {
      setState(() {
        _markers = markers;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isGPSReady) {
      return Center(child: CircularProgressIndicator());
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(latitude!, longitude!),
        zoom: 18.0,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      markers: _markers,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
      },
      mapType: MapType.normal,
    );
  }
}
