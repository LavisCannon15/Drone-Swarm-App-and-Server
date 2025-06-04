import 'dart:io';
import 'package:flutter/material.dart';
import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';

class TelemetryWidget extends StatefulWidget {
  @override
  _TelemetryWidgetState createState() => _TelemetryWidgetState();
}

class _TelemetryWidgetState extends State<TelemetryWidget> {
  final GPSService gpsService = GPSService();
  final SimulatedGPSService simulatedGPSService = SimulatedGPSService();
  
  double latitude = 0.0;
  double longitude = 0.0;
  String speed = "0.0";

  @override
  void initState() {
    super.initState();
    startLocationUpdates();
  }

  void startLocationUpdates() {
    if (Platform.isAndroid || Platform.isIOS) {
      gpsService.locationStream.listen((locationData) {
        setState(() {
          latitude = locationData["latitude"] ?? 0.0;
          longitude = locationData["longitude"] ?? 0.0;
          speed = locationData["speed"].toString();
        });
      });
    } else {
      simulatedGPSService.locationStream.listen((locationData) {
        setState(() {
          latitude = locationData["latitude"] ?? 0.0;
          longitude = locationData["longitude"] ?? 0.0;
          speed = locationData["speed"].toString();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Latitude: ${latitude.toStringAsFixed(6)}"),
          Text("Longitude: ${longitude.toStringAsFixed(6)}"),
          Text("Speed: $speed m/s"),
        ],
      ),
    );
  }
}
