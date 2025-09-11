import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_manager.dart';
import '../services/websocket_service.dart';
import '../services/gps_service.dart';
import '../services/simulated_gps_service.dart';

class ModeSelector extends StatefulWidget {
  final Function(String) onModeSelected;

  const ModeSelector({super.key, required this.onModeSelected});

  @override
  _ModeSelectorState createState() => _ModeSelectorState();
}

class _ModeSelectorState extends State<ModeSelector> {
  String selectedMode = "Normal";

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  // ✅ Ensure "Normal" is always the default mode when the app starts
  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    String savedMode = prefs.getString('selectedMode') ?? "Normal";

    if (savedMode != "Normal") {
      // ✅ Reset to "Normal" when the app starts
      await prefs.setString('selectedMode', "Normal");
      savedMode = "Normal";
    }

    if (!mounted) return;
    setState(() {
      selectedMode = savedMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final mode = await _showModeSelectorDialog(context);
        if (mode != null) {
          if (!mounted) return;
          setState(() {
            selectedMode = mode;
          });
          widget.onModeSelected(mode);

          // ✅ Save selected mode to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('selectedMode', mode);

          await WebSocketService().sendCommand('mode_update', {
            'orbit_around_user': mode == 'Orbit',
            'swap_positions': mode == 'Swap Positions',
            'rotate_triangle_formation': mode == 'Rotate Triangle',
          });

          // Update cached values so GPS updates reflect the new mode
          await GPSService().refreshSettings();
          await SimulatedGPSService().refreshSettings();

          LogManager().addLog("🎛️ Mode changed to: $mode");
        }
      },

      child: Text(selectedMode),
    );
  }

  Future<String?> _showModeSelectorDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text("Select Mode"),
          children: <Widget>[
            _buildModeOption(context, "Normal"),
            _buildModeOption(context, "Orbit"),
            _buildModeOption(context, "Rotate Triangle"),
            _buildModeOption(context, "Swap Positions"),
          ],
        );
      },
    );
  }

  Widget _buildModeOption(BuildContext context, String mode) {
    return SimpleDialogOption(
      onPressed: () {
        LogManager().addLog("📌 Mode selected: $mode");
        Navigator.pop(context, mode);
      },
      child: Text(mode),
    );
  }
}
