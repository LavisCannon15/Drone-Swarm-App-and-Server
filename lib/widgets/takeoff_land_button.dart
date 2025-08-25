import 'dart:async';
import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class TakeOffLandButton extends StatefulWidget {
  const TakeOffLandButton({super.key});
  
  @override
  _TakeOffLandButtonState createState() => _TakeOffLandButtonState();
}

class _TakeOffLandButtonState extends State<TakeOffLandButton> {
  final WebSocketService webSocketService = WebSocketService();
  bool isTakeOff = true;
  bool isLanding = false;
  StreamSubscription? _landingSub;

  @override
  void initState() {
    super.initState();
    _landingSub = webSocketService.landingCompleteStream.listen((_) {
      if (!mounted) return;
      setState(() {
        isTakeOff = true;
        isLanding = false;
      });
      LogManager().addLog("🔄 Button toggled: Now Take Off");
    });
  }

  @override
  void dispose() {
    _landingSub?.cancel();
    super.dispose();
  }

  Future<void> handleTakeOffLand() async {
    if (isTakeOff) {
      await webSocketService.sendStartOperations();
      if (!mounted) return;
      setState(() {
        isTakeOff = false;
      });
      LogManager().addLog("🔄 Button toggled: Now Land");
    } else {
      if (!mounted) return;
      setState(() {
        isLanding = true;
      });
      await webSocketService.sendStopOperations();
      LogManager().addLog("🛬 Landing initiated...");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLanding ? null : handleTakeOffLand,
      child: Text(isLanding
          ? "Landing..."
          : isTakeOff
              ? "Take Off"
              : "Land"),
    );
  }
}
