import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

class DroneMessagesScreen extends StatefulWidget {
  const DroneMessagesScreen({super.key});

  @override
  State<DroneMessagesScreen> createState() => _DroneMessagesScreenState();
}

class _DroneMessagesScreenState extends State<DroneMessagesScreen> {
  @override
  Widget build(BuildContext context) {
    final service = WebSocketService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drone Messages'),
      ),
      body: Container(
        color: Colors.black,
        child: StreamBuilder<void>(
          stream: service.droneStatusStream,
          builder: (context, snapshot) {
            final status = service.droneStatus;
            if (status.isEmpty) {
              return const Center(
                child: Text(
                  'No messages',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }
            return ListView(
              children: status.entries
                  .map((entry) => _buildDroneSection(entry.key, entry.value))
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDroneSection(String droneId, List<String> messages) {
    return ExpansionTile(
      collapsedBackgroundColor: Colors.grey[900],
      backgroundColor: Colors.black,
      iconColor: Colors.white,
      textColor: Colors.white,
      title: Text(droneId, style: const TextStyle(color: Colors.white)),
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(
                messages[index],
                style: const TextStyle(color: Colors.white),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => WebSocketService().clearDroneStatus(droneId),
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
  }
}
