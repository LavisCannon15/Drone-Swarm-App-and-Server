import 'dart:async';
import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class DroneInfoBottomSheet extends StatefulWidget {
  const DroneInfoBottomSheet({super.key});

  @override
  _DroneInfoBottomSheetState createState() => _DroneInfoBottomSheetState();
}

class _DroneInfoBottomSheetState extends State<DroneInfoBottomSheet> {
  final WebSocketService webSocketService = WebSocketService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  StreamSubscription<void>? _telemetrySubscription;
  Timer? _debounceTimer;

  static const double _minSize = 0.03;
  static const double _maxSize = 0.8;

  @override
  void initState() {
    super.initState();
    _telemetrySubscription = webSocketService.telemetryStream.listen((_) {
      if (!mounted) return;
      // Skip updates when the sheet is collapsed or not attached.
      if (!_sheetController.isAttached || _sheetController.size <= _minSize) {
        return;
      }

      // Debounce telemetry updates to avoid excessive rebuilds.
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        refreshDroneTelemetry();
      });
    });

    LogManager().addLog("📡 Started telemetry updates");
  }

  void refreshDroneTelemetry() {
    setState(() {});
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _debounceTimer?.cancel();
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
                  itemCount: webSocketService.telemetryData.length,
                  itemBuilder: (context, index) {
                    final drone =
                        webSocketService.telemetryData.values.elementAt(index);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 12.0,
                      ),
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
                                drone["drone_id"]?.toString() ??
                                    "Unknown Drone",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("📍 Position"),
                              _buildDataRow(
                                "Latitude",
                                drone["latitude"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "Longitude",
                                drone["longitude"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "Altitude",
                                drone["altitude"] != null
                                    ? "${drone["altitude"]} m"
                                    : "N/A",
                              ),
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
                              _buildDataRow(
                                "Groundspeed",
                                drone["groundspeed"] != null
                                    ? "${drone["groundspeed"]} m/s"
                                    : "N/A",
                              ),
                              _buildDataRow(
                                "Airspeed",
                                drone["airspeed"] != null
                                    ? "${drone["airspeed"]} m/s"
                                    : "N/A",
                              ),
                              SizedBox(height: 10),
                              _buildSectionHeading("📡 GPS"),
                              _buildDataRow(
                                "Satellites",
                                drone["gps"] is Map &&
                                        drone["gps"]["satellites_visible"] !=
                                            null
                                    ? drone["gps"]["satellites_visible"]
                                          .toString()
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
                              _buildDataRow(
                                "Armed",
                                drone["armed"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "Vehicle Mode",
                                drone["vehicle_mode"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "System Status",
                                drone["system_status"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "Heartbeat",
                                drone["heartbeat"]?.toString() ?? "N/A",
                              ),
                              _buildDataRow(
                                "Message Factory",
                                drone["message_factory"]?.toString() ??
                                    "N/A",
                              ),
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
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.blueGrey,
      ),
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
