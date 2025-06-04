import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:latlong2/latlong.dart';
import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';
import '../services/websocket_service.dart';

class XYGraphWidget extends StatefulWidget {
  @override
  _XYGraphWidgetState createState() => _XYGraphWidgetState();
}

class _XYGraphWidgetState extends State<XYGraphWidget> {
  final GPSService gpsService = GPSService();
  final SimulatedGPSService simulatedGPSService = SimulatedGPSService();
  final WebSocketService webSocketService = WebSocketService();

  Map<String, LatLng> droneLocations = {};
  LatLng userLocation = LatLng(0.0, 0.0);

  StreamSubscription? _locationSubscription;
  StreamSubscription? _telemetrySubscription;

  @override
  void initState() {
    super.initState();
    startLocationUpdates();
    startDroneTelemetryUpdates();
  }

  void startLocationUpdates() {
    _locationSubscription?.cancel(); // ✅ Ensure no duplicate subscriptions

    if (Platform.isAndroid || Platform.isIOS) {
      _locationSubscription = gpsService.locationStream.listen((locationData) {
        if (!mounted) return; // ✅ Prevent calling setState() after dispose
        setState(() {
          userLocation = LatLng(locationData["latitude"], locationData["longitude"]);
        });
      });
    } else {
      _locationSubscription = simulatedGPSService.locationStream.listen((locationData) {
        if (!mounted) return;
        setState(() {
          userLocation = LatLng(locationData["latitude"], locationData["longitude"]);
        });
      });
    }
  }

  void startDroneTelemetryUpdates() {
    _telemetrySubscription?.cancel(); // Prevent multiple subscriptions
    _telemetrySubscription = webSocketService.serverLogStream.listen((_) {
      if (!mounted) return; // Ensure widget is still in tree before updating state
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


  @override
  void dispose() {
    _locationSubscription?.cancel(); // ✅ Stop GPS updates
    _telemetrySubscription?.cancel(); // ✅ Stop WebSocket updates
    super.dispose();
  }

@override
  Widget build(BuildContext context) {
    print("🔄 XYGraphWidget rebuilding at ${DateTime.now().toIso8601String()}");

    //final List<LatLng> allLocations = [...droneLocations.values, userLocation];

    // ✅ Set user location as the center of the graph
    double centerLongitude = userLocation.longitude;
    double centerLatitude = userLocation.latitude;

    // ✅ Define a fixed range around the user to ensure proper scaling
    double range = 0.0005;  // Adjust this value for zoom level

    double minLongitude = centerLongitude - range;
    double maxLongitude = centerLongitude + range;
    double minLatitude = centerLatitude - range;
    double maxLatitude = centerLatitude + range;

    final List<FlSpot> droneSpots = droneLocations.entries.map((entry) {
      final location = entry.value;
      return FlSpot(location.longitude, location.latitude);
    }).toList();

    final FlSpot userSpot = FlSpot(userLocation.longitude, userLocation.latitude);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(2, 2),
            ),
          ],
        ),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(show: true),
            borderData: FlBorderData(
              show: true,
              border: Border(
                left: BorderSide(color: Colors.black, width: 1),
                bottom: BorderSide(color: Colors.black, width: 1),
                top: BorderSide(color: Colors.transparent, width: 1),
                right: BorderSide(color: Colors.transparent, width: 1),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(value.toStringAsFixed(5), style: TextStyle(fontSize: 10));
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  interval: (maxLongitude - minLongitude) / 4,
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(value.toStringAsFixed(5), style: TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            minX: minLongitude,
            maxX: maxLongitude,
            minY: minLatitude,
            maxY: maxLatitude,
            lineBarsData: [
              LineChartBarData(
                spots: droneSpots,
                isCurved: false,
                isStrokeCapRound: false,
                barWidth: 0,
                color: Colors.transparent,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) {
                    return FlDotCirclePainter(
                      radius: 4,
                      color: Colors.blue,
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(show: false),
              ),
              LineChartBarData(
                spots: [userSpot],
                isCurved: false,
                isStrokeCapRound: false,
                barWidth: 0,
                color: Colors.transparent,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) {
                    return FlDotCirclePainter(
                      radius: 5,
                      color: Colors.red,
                      strokeWidth: 1.5,
                      strokeColor: Colors.black,
                    );
                  },
                ),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
