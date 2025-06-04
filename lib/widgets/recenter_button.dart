import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/desktop_map_widget.dart';
import '../widgets/map_widget.dart';

class RecenterButton extends StatelessWidget {
  final GlobalKey<MapWidgetState>? mobileMapKey;
  final GlobalKey<DesktopMapWidgetState>? desktopMapKey;

  RecenterButton({
    this.mobileMapKey,
    this.desktopMapKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
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
          Icons.location_searching,
          color: Colors.black,
          size: 24,
        ),
        onPressed: () {
          if (Platform.isAndroid || Platform.isIOS) {
            if (mobileMapKey != null && mobileMapKey!.currentState != null) {
              mobileMapKey!.currentState!.recenterOnUser();
            }
          } else {
            if (desktopMapKey != null && desktopMapKey!.currentState != null) {
              desktopMapKey!.currentState!.recenterOnUser();
            }
          }
        },
      ),
    );
  }
}
