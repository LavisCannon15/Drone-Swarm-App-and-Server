import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_manager.dart';
import '../services/network_discovery.dart'; // <-- import

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
    setState(() {
      drones = saved.map((e) {
        final parts = e.split(';');
        return {'name': parts[0], 'ip': parts[1]};
      }).toList();
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
    setState(() => drones.clear());
    LogManager().addLog("Cleared all saved drones.");
  }

  Future<void> _scanForDrones() async {
    // 1) trigger the scan
    final ips = await DroneDiscoveryService.discover();

    // 2) show them in a popup
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discovered Drones'),
        content: ips.isEmpty
            ? Text('No drones found on this network.')
            : Container(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ips.length,
                  itemBuilder: (_, i) {
                    final ip = ips[i];
                    return ListTile(
                      title: Text(ip),
                      trailing: IconButton(
                        icon: Icon(Icons.add),
                        onPressed: () {
                          setState(() {
                            drones.add({
                              'name': 'Drone ${drones.length + 1}',
                              'ip': ip,
                            });
                          });
                          _saveDrones();
                          Navigator.of(context).pop(); // or just remove that entry
                        },
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Manage Drones"),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            tooltip: "Clear All Drones (Debug)",
            onPressed: _clearDrones,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Manual IP entry
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: "Drone IP Address",
                      hintText: "e.g., 192.168.1.50:14550",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(onPressed: _addDrone, child: Text("Add")),
              ],
            ),
            SizedBox(height: 20),

            // Saved drones list
            Expanded(
              child: ListView.builder(
                itemCount: drones.length,
                itemBuilder: (_, index) {
                  final drone = drones[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      leading: Image.asset(
                        "assets/icons/drone_marker.png",
                        width: 40,
                        height: 40,
                      ),
                      title: Text(drone["name"]!),
                      subtitle: Text("IP: ${drone["ip"]}"),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
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
      // Scan button fixed at bottom of screen
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          icon: Icon(Icons.wifi_tethering),
          label: Text("Scan for Drones"),
          onPressed: _scanForDrones,
          style: ElevatedButton.styleFrom(minimumSize: Size.fromHeight(50)),
        ),
      ),
    );
  }
}
