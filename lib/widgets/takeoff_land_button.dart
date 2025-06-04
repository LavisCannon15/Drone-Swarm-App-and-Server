import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class TakeOffLandButton extends StatefulWidget {
  @override
  _TakeOffLandButtonState createState() => _TakeOffLandButtonState();
}

class _TakeOffLandButtonState extends State<TakeOffLandButton> {
  final WebSocketService webSocketService = WebSocketService();
  bool isTakeOff = true;

  Future<void> handleTakeOffLand() async {
    if (isTakeOff) {
      await webSocketService.sendStartOperations();
    } else {
      await webSocketService.sendStopOperations();
    }

    // Toggle the button state
    setState(() {
      isTakeOff = !isTakeOff;
    });

    print("🔄 Button toggled: Now ${isTakeOff ? "Take Off" : "Land"}");
    LogManager().addLog("🔄 Button toggled: Now ${isTakeOff ? "Take Off" : "Land"}");
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: handleTakeOffLand,
      child: Text(isTakeOff ? "Take Off" : "Land"),
    );
  }
}
