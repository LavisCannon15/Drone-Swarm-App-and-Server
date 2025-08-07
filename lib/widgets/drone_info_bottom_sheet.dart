import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import '../services/log_manager.dart';

class DroneInfoBottomSheet extends StatefulWidget {
  const DroneInfoBottomSheet({super.key});

  @override
  _DroneInfoBottomSheetState createState() => _DroneInfoBottomSheetState();
}

class _DroneInfoBottomSheetState extends State<DroneInfoBottomSheet> {
  final WebSocketService webSocketService = WebSocketService();
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  Map<String, dynamic> droneTelemetry = {};
  List<Map<String, dynamic>> droneData = [];
  StreamSubscription? _telemetrySubscription;

  static const double _minSize = 0.03;
  static const double _maxSize = 0.8;

  @override
  void initState() {
    super.initState();
    _telemetrySubscription =
        webSocketService.telemetryStream.listen((_) {
      if (!mounted) return;
      refreshDroneTelemetry();
    });

    if (kDebugMode) {
      print("📡 Started telemetry updates");
    }
    LogManager().addLog("📡 Started telemetry updates");
  }

  void refreshDroneTelemetry() {
    setState(() {
      // map raw telemetry into LatLng
      droneTelemetry = webSocketService.telemetryData.map(
        (id, data) => MapEntry(
          id,
          latlong2.LatLng(
            (data["latitude"] as num?)?.toDouble() ?? 0.0,
            (data["longitude"] as num?)?.toDouble() ?? 0.0,
          ),
        ),
      );

      // build list of readable maps
      droneData = webSocketService.telemetryData.values.map((data) {
        return {
          "id": data["drone_id"],
          "latitude": data["latitude"],
          "longitude": data["longitude"],
          "altitude": "${data["altitude"]} m",
          "velocity": data["velocity"],
          "battery": data["battery"],
          "gps": data["gps"],
          "groundspeed": "${data["groundspeed"]} m/s",
          "airspeed": "${data["airspeed"]} m/s",
          "armed": data["armed"].toString(),
          "vehicle_mode": data["vehicle_mode"],
          "system_status": data["system_status"],
          "heartbeat": "${data["heartbeat"]}",
          "message_factory": data["message_factory"].toString(),
        };
      }).toList();
    });
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _minSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Column(
            children: [
              // drag handle for both touch & mouse
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  final height = MediaQuery.of(context).size.height;
                  final delta = details.primaryDelta! / height;
                  // .size is non-nullable, so use it directly
                  double newSize = _sheetController.size - delta;
                  newSize = newSize.clamp(_minSize, _maxSize);
                  _sheetController.jumpTo(newSize);
                },
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // the scrollable list of drone info
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: droneData.length,
                  itemBuilder: (context, index) {
                    final drone = droneData[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                drone["id"] ?? "Unknown Drone",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("📍 Position"),
                              _buildDataRow("Latitude", drone["latitude"]?.toString() ?? "N/A"),
                              _buildDataRow("Longitude", drone["longitude"]?.toString() ?? "N/A"),
                              _buildDataRow("Altitude", drone["altitude"]?.toString() ?? "N/A"),
                              SizedBox(height: 10),
                              _buildSectionHeading("⚡ Velocity"),
                              _buildDataRow(
                                "Velocity (vx, vy, vz)",
                                drone["velocity"] is List
                                    ? drone["velocity"].toString()
                                    : "N/A",
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("🔋 Battery"),
                              _buildDataRow(
                                "Battery Level",
                                drone["battery"] is Map &&
                                        drone["battery"]["level"] != null
                                    ? "${drone["battery"]["level"]}%"
                                    : "N/A",
                              ),
                              _buildDataRow(
                                "Voltage",
                                drone["battery"] is Map &&
                                        drone["battery"]["voltage"] != null
                                    ? "${drone["battery"]["voltage"]} V"
                                    : "N/A",
                              ),
                              _buildDataRow(
                                "Current",
                                drone["battery"] is Map &&
                                        drone["battery"]["current"] != null
                                    ? "${drone["battery"]["current"]} A"
                                    : "N/A",
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("🚀 Speed"),
                              _buildDataRow("Groundspeed", drone["groundspeed"] ?? "N/A"),
                              _buildDataRow("Airspeed", drone["airspeed"] ?? "N/A"),
                              SizedBox(height: 10),
                              _buildSectionHeading("📡 GPS"),
                              _buildDataRow(
                                "Satellites",
                                drone["gps"] is Map &&
                                        drone["gps"]["satellites_visible"] != null
                                    ? drone["gps"]["satellites_visible"].toString()
                                    : "N/A",
                              ),
                              _buildDataRow(
                                "Fix Type",
                                drone["gps"] is Map &&
                                        drone["gps"]["fix_type"] != null
                                    ? drone["gps"]["fix_type"].toString()
                                    : "N/A",
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("⚙️ System Status"),
                              _buildDataRow("Armed", drone["armed"] ?? "N/A"),
                              _buildDataRow("Vehicle Mode", drone["vehicle_mode"] ?? "N/A"),
                              _buildDataRow("System Status", drone["system_status"] ?? "N/A"),
                              _buildDataRow("Heartbeat", drone["heartbeat"] ?? "N/A"),
                              _buildDataRow("Message Factory", drone["message_factory"] ?? "N/A"),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeading(String heading) {
    return Text(
      heading,
      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("$label:", style: TextStyle(fontWeight: FontWeight.bold)),
        Text(value),
      ],
    );
  }
}
