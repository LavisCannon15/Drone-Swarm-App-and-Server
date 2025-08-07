# Drone Swarm App & Server

A Flutter control station and Python backend for commanding and monitoring a swarm of drones in real time.  
Operators can track multiple vehicles, issue flight commands, and view telemetry even when the app runs in the background on Android.

## Features
- Real‑time telemetry stream (GPS, speed, battery, etc.)
- Interactive map with Google Maps or FMTC tiles
- Drone management: add, remove, connect, and disconnect endpoints
- Console log viewer and XY telemetry graph
- Background execution on Android via foreground service
- Python server built with DroneKit for multi‑drone control

## Project Structure
```

├── lib/               # Flutter application source\
│   ├── screens/       # UI pages (home, settings, console, etc.)\
│   ├── services/      # WebSocket, GPS, logging\
│   └── widgets/       # Reusable UI components\
├── linux/             # Python server (DroneKit, telemetry, WebSocket)\
└── assets/            # Icons and other static assets

```

## Requirements
- Flutter SDK ≥ 3.6.0
- Python 3.9+ with `dronekit`, `geopy`, and `websockets`

## Running the Server
```bash
cd linux
pip install dronekit geopy websockets
python websocket_server.py
```

## Running the App

```bash
flutter pub get
flutter run
```

1. Launch the server first.
2. In the app, open **Settings** to set the server address.
3. Use **Manage Drones** to add drone endpoints.
4. Tap **Connect** and start sending telemetry.

## Background Execution (Android)

The app uses a foreground service to keep GPS and WebSocket connections alive after the Home button is pressed.\
Ensure location permission is granted and the app is exempt from battery optimizations.

## License

\[Add your license here]

