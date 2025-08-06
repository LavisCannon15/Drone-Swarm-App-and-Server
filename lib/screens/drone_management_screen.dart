import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_manager.dart';

class DroneManagementScreen extends StatefulWidget {
  @override
  _DroneManagementScreenState createState() {
    LogManager().addLog("DroneManagementScreen created.");
    return _DroneManagementScreenState();
  }
}

class _DroneManagementScreenState extends State<DroneManagementScreen> {
  final TextEditingController _ipController = TextEditingController();
  List<Map<String, String>> drones = [];

  @override
  void initState() {
    super.initState();
    LogManager().addLog("DroneManagementScreen initState called.");
    _loadDrones();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _loadDrones() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('drones') ?? [];
    if (!mounted) return;
    setState(() {
      drones = [];
      for (final e in saved) {
        final parts = e.split(';');
        if (parts.length < 2) {
          LogManager().addLog('Malformed drone entry: $e');
          continue;
        }
        drones.add({'name': parts[0], 'ip': parts[1]});
      }
    });
  }

  Future<void> _saveDrones() async {
    final prefs = await SharedPreferences.getInstance();
    final data = drones.map((d) => "${d['name']};${d['ip']}").toList();
    await prefs.setStringList('drones', data);
  }

  void _addDrone() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      LogManager().addLog("Error: Drone IP address is empty.");
      return;
    }
    setState(() {
      drones.add({'name': 'Drone ${drones.length + 1}', 'ip': ip});
      _ipController.clear();
    });
    _saveDrones();
  }

  Future<void> _clearDrones() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drones');
    if (!mounted) return;
    setState(() => drones.clear());
    LogManager().addLog("Cleared all saved drones.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Drones"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: "Clear All Drones (Debug)",
            onPressed: _clearDrones,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: "Drone IP Address",
                      hintText: "e.g., 192.168.1.50:14550",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _addDrone, child: const Text("Add")),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: drones.length,
                itemBuilder: (_, index) {
                  final drone = drones[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      leading: Image.asset(
                        "assets/icons/drone_marker.png",
                        width: 40,
                        height: 40,
                      ),
                      title: Text(drone["name"]!),
                      subtitle: Text("IP: ${drone["ip"]}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() => drones.removeAt(index));
                          _saveDrones();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}