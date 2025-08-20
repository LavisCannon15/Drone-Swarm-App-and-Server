import 'package:flutter/material.dart';
import '../services/simulated_gps_service.dart';

class MovementToggleButton extends StatefulWidget {
  final SimulatedGPSService gpsService;
  const MovementToggleButton({required this.gpsService, super.key});

  @override
  State<MovementToggleButton> createState() => _MovementToggleButtonState();
}

class _MovementToggleButtonState extends State<MovementToggleButton> {
  late bool _stationary;

  @override
  void initState() {
    super.initState();
    _stationary = widget.gpsService.isStationary;
  }

  void _toggle() {
    setState(() {
      _stationary = !_stationary;
    });
    widget.gpsService.setStationary(_stationary);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45,
      height: 45,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(2, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(
          _stationary ? Icons.play_arrow : Icons.pause,
          color: Colors.black,
          size: 24,
        ),
        onPressed: _toggle,
      ),
    );
  }
}

