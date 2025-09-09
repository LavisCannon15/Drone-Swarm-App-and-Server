import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class KillSwitchButton extends StatelessWidget {
  const KillSwitchButton({super.key});

  Future<void> _triggerKillSwitch(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Emergency Stop'),
        content: const Text(
            'Are you sure you want to immediately land and disarm all drones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WebSocketService().sendForceDisarm();
      LogManager().addLog("🛑 Kill switch activated");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => _triggerKillSwitch(context),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Emergency Stop',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
