import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class KillSwitchButton extends StatelessWidget {
  const KillSwitchButton({super.key});

  Future<void> _triggerKillSwitch() async {
    await WebSocketService().sendForceDisarm();
    LogManager().addLog("🛑 Kill switch activated");
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
      onPressed: _triggerKillSwitch,
      child: const Text('Emergency Stop'),
    );
  }
}
