import 'dart:async';
import 'dart:io';

/// Service to discover drone IPs by listening for MAVLink packets on UDP port 14550.
class DroneDiscoveryService {
  /// Listens on UDP [port] for MAVLink v1 (0xFE) or v2 (0xFD) headers
  /// and returns a list of distinct "ip:port" strings seen in [timeout].
  static Future<List<String>> discover({
    int port = 14550,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // 1) Bind a UDP socket on all interfaces
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
    );
    final found = <String>{};

    // 2) Listen for incoming datagrams
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null && dg.data.isNotEmpty) {
          final header = dg.data[0];
          // Check for MAVLink packet start bytes
          if (header == 0xFE || header == 0xFD) {
            found.add('${dg.address.address}:$port');
          }
        }
      }
    });

    // 3) Wait for any MAVLink traffic up to the timeout, then close
    await Future.delayed(timeout);
    socket.close();

    return found.toList();
  }
}
