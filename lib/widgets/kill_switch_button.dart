import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../services/log_manager.dart';

class KillSwitchButton extends StatelessWidget {
  const KillSwitchButton({super.key});

  Future<void> _confirmAndTrigger(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Emergency Stop'),
        content: const Text(
            'This will immediately disarm all drones. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await WebSocketService().sendForceDisarm();
      LogManager().addLog("🛑 Kill switch activated");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
      onPressed: () => _confirmAndTrigger(context),
      child: const Text('Emergency Stop'),
    );
  }
}
