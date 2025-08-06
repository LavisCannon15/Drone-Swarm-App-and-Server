import asyncio
import websockets
import socket
import json
import threading
from dronekit import connect
from drone_operations import operate_drones
from global_vars import stop_operations_event


vehicles = {}  # Store connected drones
server_log_clients = set()  # Store connected clients for log streaming
drone_command_data = {"latitude": 0.0, "longitude": 0.0, "speed": 0.0}  # Holds GPS & movement settings

async def send_telemetry():
    """
    Periodically sends telemetry data for each connected drone to the client.
    """
    while True:
        telemetry_data = []
        for drone_id, vehicle in vehicles.items():
            try:
                telemetry = {
                    "drone_id": drone_id,
                    "latitude": vehicle.location.global_relative_frame.lat,
                    "longitude": vehicle.location.global_relative_frame.lon,
                    "altitude": vehicle.location.global_relative_frame.alt,
                    "velocity": vehicle.velocity,
                    "battery": {
                        "voltage": vehicle.battery.voltage,
                        "current": vehicle.battery.current,
                        "level": vehicle.battery.level,
                    },
                    "gps": {
                        "fix_type": vehicle.gps_0.fix_type,
                        "satellites_visible": vehicle.gps_0.satellites_visible,
                    },
                    "groundspeed": vehicle.groundspeed,
                    "airspeed": vehicle.airspeed,
                    "armed": vehicle.armed,
                    "vehicle_mode": str(vehicle.mode.name),
                    "ekf_ok": vehicle.ekf_ok,
                    "system_status": str(vehicle.system_status.state),
                    "heartbeat": vehicle.last_heartbeat,
                    "message_factory": str(vehicle.message_factory),
                }
                telemetry_data.append(telemetry)
            except Exception as e:
                await log_message(f"Error retrieving telemetry for {drone_id}: {e}")

        telemetry_message = json.dumps({
            "command": "telemetry",
            "data": telemetry_data
        })

        for client in list(server_log_clients):
            try:
                await client.send(telemetry_message)
            except websockets.exceptions.ConnectionClosed:
                server_log_clients.remove(client)  # Remove disconnected clients

        await asyncio.sleep(2)  # Adjust the interval as needed

async def handle_client(websocket, path):
    """
    Handles incoming WebSocket connections and processes commands.
    """
    await log_message("📡 New client connected.")

    try:
        async for message in websocket:
            data = json.loads(message)
            command = data.get("command")
            params = data.get("params", {})

            # ✅ Skip logging "user_gps" to prevent spam
            if command == "user_gps":
                await handle_user_gps(params)
                continue  # ✅ Skip logging

            await log_message(f"📩 Received: {message}")  # ✅ Log other commands

            if command == "connect":
                await handle_connect_command(websocket, params)
            elif command == "start_operations":
                await handle_start_operations(params)
            elif command == "stop_operations":
                await handle_stop_operations()
            elif command == "subscribe_logs":
                server_log_clients.add(websocket)
                await log_message("✅ Client subscribed to server logs.")
            else:
                await log_message(f"⚠️ Unknown command: {command}")
                await websocket.send(json.dumps({
                    "status": "error",
                    "message": f"Unknown command: {command}"
                }))

    except websockets.exceptions.ConnectionClosed:
        await log_message("⚠️ Client disconnected! Landing all drones.")
        await handle_stop_operations()  # ✅ Auto-land drones when client disconnects

    except Exception as e:
        # ✅ Log any unexpected errors in the server console
        await log_message(f"❌ SERVER ERROR: {str(e)}")



async def handle_connect_command(websocket, params):
    """
    Handles the 'connect' command to connect to multiple drones.
    """
    drones = params.get("drones", {})

    # ✅ Fix: Convert list to dictionary format if needed
    if isinstance(drones, list):
        drones = {f"Drone {i+1}": ip for i, ip in enumerate(drones)}

    if not drones:
        await websocket.send(json.dumps({
            "status": "error",
            "message": "No drone connections provided."
        }))
        return

    await log_message(f"Attempting to connect to drones: {drones}")

    global vehicles
    vehicles.clear()  # ✅ Clear old connections

    for drone_id, drone_ip in drones.items():
        try:
            await log_message(f"Connecting {drone_id} to {drone_ip}")
            
            vehicle = connect(drone_ip, wait_ready=True)  # ✅ Connect to the drone
            vehicle.id = drone_id  # ✅ Assign a drone ID to the vehicle
            vehicles[drone_id] = vehicle  # ✅ Store in vehicles dictionary

            await log_message(f"{drone_id} connected successfully at {drone_ip}.")
        except Exception as e:
            await log_message(f"Failed to connect {drone_id}: {e}")
            await websocket.send(json.dumps({
                "status": "error",
                "drone_id": drone_id,
                "message": str(e)
            }))
            continue

    # ✅ Debug print the final stored vehicles dictionary
    await log_message(f"🔍 DEBUG: Vehicles Stored → {vehicles}")

    await websocket.send(json.dumps({
        "status": "success",
        "message": "All connection attempts completed.",
        "vehicles": {drone_id: str(vehicle) for drone_id, vehicle in vehicles.items()}  # ✅ Send back stored connections
    }))

    # ✅ Start telemetry updates immediately after connecting
    asyncio.create_task(send_telemetry())



async def handle_user_gps(params):
    """
    Handles the 'user_gps' command to receive user location and movement updates.
    """
    global drone_command_data  # Updated variable name

    latitude = params.get("latitude")
    longitude = params.get("longitude")
    speed = params.get("speed")
    offset_distance = params.get("offset_distance", 4.0)
    revolve_speed = params.get("revolve_speed", 3.0)
    revolve_offset_distance = params.get("revolve_offset_distance", 4.0)
    swap_position_speed = params.get("swap_position_speed", 2.0)  # ✅ Get Swap Position Speed
    orbit_around_user = params.get("orbit_around_user", False)
    swap_positions = params.get("swap_positions", False)
    rotate_triangle_formation = params.get("rotate_triangle_formation", False)

    if latitude is not None and longitude is not None:
        drone_command_data.update({
            "latitude": latitude,
            "longitude": longitude,
            "speed": speed,
            "offset_distance": offset_distance,
            "revolve_speed": revolve_speed,
            "revolve_offset_distance": revolve_offset_distance,
            "swap_position_speed": swap_position_speed,  # ✅ Store Swap Position Speed
            "orbit_around_user": orbit_around_user,
            "swap_positions": swap_positions,
            "rotate_triangle_formation": rotate_triangle_formation
        })

        # ✅ Debug log for confirmation
        #await log_message(f"📍 Updated User Movement Settings: {drone_command_data}")



async def handle_start_operations(params):
    """
    Handles the 'start_operations' command to initiate drone operations.
    """
    global stop_operations_event, drone_command_data

    if not vehicles:
        await log_message("🚨 No drones connected! Cannot start operations.")
        return

    await log_message("🚀 Starting drone operations...")

    stop_operations_event.clear()

    # ✅ Extract parameters from WebSocket message
    takeoff_altitude = params.get("takeoff_altitude", 3.0)
    target_altitude = params.get("target_altitude", 1.0)
    offset_distance = params.get("offset_distance", 4.0)
    revolve_speed = params.get("revolve_speed", 1.0)
    revolve_offset_distance = params.get("revolve_offset_distance", 4.0)
    swap_position_speed = params.get("swap_position_speed", 2.0)  # ✅ Get Swap Position Speed

    drone_command_data.update({
        "offset_distance": offset_distance,
        "orbit_around_user": params.get("orbit_around_user", False),
        "swap_positions": params.get("swap_positions", False),
        "rotate_triangle_formation": params.get("rotate_triangle_formation", False),
        "revolve_speed": revolve_speed,
        "revolve_offset_distance": revolve_offset_distance,
        "swap_position_speed": swap_position_speed,  # ✅ Store Swap Position Speed
    })

    # ✅ Only pass the list of `Vehicle` objects, NOT tuples
    drone_list = list(vehicles.values())

    drone_thread = threading.Thread(
        target=operate_drones, 
        args=(drone_list, takeoff_altitude, target_altitude, drone_command_data)
    )
    drone_thread.start()






async def handle_stop_operations():
    """
    Handles the 'stop_operations' command to land all drones.
    """
    global stop_operations_event
    stop_operations_event.set()
    await log_message("🛬 Stop operations signal received! Landing all drones.")


async def log_message(message):
    """
    Logs a message to the console and broadcasts it to all subscribed WebSocket clients.
    """
    print(message)  # ✅ Print to the server console

    message_data = json.dumps({"command": "log", "message": message})

    # ✅ Send log messages to all connected WebSocket clients
    disconnected_clients = set()
    for client in server_log_clients:
        try:
            await client.send(message_data)
        except websockets.exceptions.ConnectionClosed:
            disconnected_clients.add(client)  # Mark disconnected clients

    # ✅ Remove disconnected clients from `server_log_clients`
    for client in disconnected_clients:
        server_log_clients.remove(client)


async def main():
    """
    Starts the WebSocket server.
    """
    server = await websockets.serve(handle_client, "0.0.0.0", 5000)
    await log_message("WebSocket server running at ws://0.0.0.0:5000")
    await server.wait_closed()

if __name__ == "__main__":
    asyncio.run(main())
