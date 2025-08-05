import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';
import '../services/websocket_service.dart';

class DesktopMapWidget extends StatefulWidget {
  
  const DesktopMapWidget({super.key});

  @override
  DesktopMapWidgetState createState() => DesktopMapWidgetState();
}

class DesktopMapWidgetState extends State<DesktopMapWidget> {
  late final MapController mapController;
  late final FMTCTileProvider tileProvider;
  bool isLoadingCache = true;

  final GPSService gpsService = GPSService();
  final SimulatedGPSService simulatedGPSService = SimulatedGPSService();
  final WebSocketService webSocketService = WebSocketService();

  LatLng userLocation = LatLng(0.0, 0.0);
  Map<String, LatLng> droneLocations = {};

  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  StreamSubscription<dynamic>? _telemetrySubscription;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _initTileProvider();
    _startLocationUpdates();
    _startDroneTelemetryStream();
  }

  Future<void> _initTileProvider() async {
    setState(() => isLoadingCache = true);

    tileProvider = FMTCTileProvider(
      stores: {'carto_cache': BrowseStoreStrategy.read},
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
      cachedValidDuration: Duration(days: 1),
      useOtherStoresAsFallbackOnly: false,
      recordHitsAndMisses: false,
    );

    setState(() => isLoadingCache = false);
  }

  void _startLocationUpdates() {
    final stream = (Platform.isAndroid || Platform.isIOS)
        ? gpsService.locationStream
        : simulatedGPSService.locationStream;

    _locationSubscription = stream.listen((locationData) {
      if (!mounted) return;
      setState(() {
        userLocation = LatLng(
          (locationData["latitude"] as num).toDouble(),
          (locationData["longitude"] as num).toDouble(),
        );
      });
    });
  }

  /// Subscribe to live telemetry rather than polling
  void _startDroneTelemetryStream() {
    _telemetrySubscription = webSocketService.telemetryStream.listen((_) {
      if (!mounted) return;
      setState(() {
        droneLocations = webSocketService.telemetryData.map(
          (id, data) => MapEntry(
            id,
            LatLng(
              (data["latitude"] as num?)?.toDouble() ?? 0.0,
              (data["longitude"] as num?)?.toDouble() ?? 0.0,
            ),
          ),
        );
      });
    });
  }

  void recenterOnUser() {
    if (mounted) {
      mapController.move(userLocation, mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _telemetrySubscription?.cancel();
    simulatedGPSService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingCache) {
      return Center(child: CircularProgressIndicator());
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: userLocation,
        initialZoom: 18.0,
        minZoom: 5.0,
        maxZoom: 18.0,
                interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        backgroundColor: const Color(0xFFE0E0E0),
      ),
      children: [
        TileLayer(
          urlTemplate:
              "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
          subdomains: ['a', 'b', 'c'],
          tileProvider: tileProvider,
          keepBuffer: 3,
          retinaMode: true,
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint("❌ Failed to load tile: $tile, Error: $error");
          },
        ),
        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    markers.add(
      Marker(
        point: userLocation,
        width: 32.0,
        height: 32.0,
        child: Image.asset(
          'assets/icons/user_marker.png',
          width: 32,
          height: 32,
        ),
      ),
    );

    markers.addAll(
      droneLocations.entries.map((entry) {
        return Marker(
          point: entry.value,
          width: 32.0,
          height: 32.0,
          child: Image.asset(
            'assets/icons/drone_marker.png',
            width: 32,
            height: 32,
          ),
        );
      }).toList(),
    );

    return markers;
  }
}
