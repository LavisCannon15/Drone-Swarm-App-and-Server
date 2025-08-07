import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/desktop_map_widget.dart';
import '../widgets/map_widget.dart';

class RecenterButton extends StatelessWidget {
  final GlobalKey<MapWidgetState>? mobileMapKey;
  final GlobalKey<DesktopMapWidgetState>? desktopMapKey;

  const RecenterButton({this.mobileMapKey, this.desktopMapKey, super.key});

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
        icon: const Icon(
          Icons.location_searching,
          color: Colors.black,
          size: 24,
        ),
        onPressed: () {
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)) {
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
