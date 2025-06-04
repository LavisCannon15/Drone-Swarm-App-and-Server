import 'package:flutter/material.dart';

class MapTypeButton extends StatefulWidget {
  final bool isMapView; // Current state (true = MapWidget, false = XYGraphWidget)
  final Function(bool) onToggle; // Callback to notify parent of state change

  MapTypeButton({required this.isMapView, required this.onToggle});

  @override
  _MapTypeButtonState createState() => _MapTypeButtonState();
}

class _MapTypeButtonState extends State<MapTypeButton> {
  late bool _isMapView; // Internal state for the button

  @override
  void initState() {
    super.initState();
    _isMapView = widget.isMapView; // Initialize with parent-provided state
  }

  void _toggleMapType() {
    setState(() {
      _isMapView = !_isMapView; // Toggle the state
    });
    widget.onToggle(_isMapView); // Notify the parent
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45, // Match size with RecenterButton
      height: 45,
      decoration: BoxDecoration(
        color: Colors.white, // Background color
        shape: BoxShape.circle, // Circular background
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
          _isMapView ? Icons.show_chart : Icons.map, // Dynamic icon
          color: Colors.black, // Icon color
          size: 24, // Icon size
        ),
        onPressed: _toggleMapType,
      ),
    );
  }
}