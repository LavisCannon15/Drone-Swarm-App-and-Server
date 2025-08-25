import asyncio
import websockets
import json
import logging
import threading
import functools
import os
import sys
import argparse
from dronekit import connect
from drone_operations import operate_drones, land
from global_vars import stop_operations_event


def _resolve_log_level() -> int:
    """Determine the logging level from CLI args or environment."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--log-level", dest="log_level")
    args, remaining = parser.parse_known_args()
    # Remove parsed args so other modules can handle their own CLI arguments
    sys.argv = [sys.argv[0]] + remaining

    level_name = args.log_level or os.getenv("LOG_LEVEL", "INFO")
    return getattr(logging, level_name.upper(), logging.INFO)


logging.basicConfig(
    level=_resolve_log_level(),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)


logger = logging.getLogger("server")


vehicles = {}  # Store connected drones
server_log_clients = set()  # Store connected clients for log streaming
drone_command_data = {"latitude": 0.0, "longitude": 0.0, "speed": 0.0}  # Holds GPS & movement settings
telemetry_task = None
drone_thread = None
landing_complete_event = threading.Event()
landing_complete_event.set()
heartbeat_stale = {}  # Track heartbeat health per drone


class WebsocketLogHandler(logging.Handler):
    """Logging handler that forwards records to WebSocket clients."""

    def __init__(self, loop):
        super().__init__()
        self.loop = loop

    def emit(self, record):
        msg = self.format(record)
        asyncio.run_coroutine_threadsafe(log_message(msg), self.loop)

async def send_telemetry():
    """
    Periodically sends telemetry data for each connected drone to the client.
    """
    while True:
        # If no clients are connected, pause before checking again to avoid busy looping.
        if not server_log_clients:
            await asyncio.sleep(5)
            continue
        telemetry_data = []
        for drone_id, vehicle in list(vehicles.items()):
            try:
                hb = getattr(vehicle, "last_heartbeat", 0)
                if hb > 5:
                    if not heartbeat_stale.get(drone_id):
                        await log_message(f"⚠️ {drone_id} heartbeat lost ({hb:.1f}s)")
                        heartbeat_stale[drone_id] = True
                    await handle_drone_disconnect(drone_id, vehicle)
                    continue
                else:
                    if heartbeat_stale.get(drone_id):
                        await log_message(f"✅ {drone_id} heartbeat restored")
                        heartbeat_stale[drone_id] = False

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
                    "heartbeat": hb,
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

async def handle_drone_disconnect(drone_id, vehicle):
    """Remove a disconnected drone and land remaining drones."""
    global vehicles, stop_operations_event

    # Always remove stale entries
    vehicles.pop(drone_id, None)
    heartbeat_stale.pop(drone_id, None)

    # Prevent repeated handling once landing is in progress
    if stop_operations_event.is_set():
        return

    await log_message(f"⚠️ {drone_id} disconnected. Landing remaining drones.")

    disconnect_message = json.dumps({
        "command": "drone_disconnected",
        "drone_id": drone_id,
    })

    for client in list(server_log_clients):
        try:
            await client.send(disconnect_message)
        except websockets.exceptions.ConnectionClosed:
            server_log_clients.remove(client)

    stop_operations_event.set()
    asyncio.create_task(handle_stop_operations())

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
            elif command == "disconnect":
                await handle_disconnect()
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
        # Only land drones if any are connected. Otherwise just clear state.
        if vehicles:
            await log_message("⚠️ Client disconnected! Landing all drones.")
            await handle_disconnect()  # ✅ Auto-land drones and disconnect when client disconnects
        else:
            await log_message("⚠️ Client disconnected! No drones to land.")
            # Clear any lingering telemetry task
            global telemetry_task
            if telemetry_task and not telemetry_task.done():
                telemetry_task.cancel()
                try:
                    await telemetry_task
                except asyncio.CancelledError:
                    pass
            telemetry_task = None

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

    connected = []
    failed = []

    async def connect_drone(drone_id, drone_ip):
        """Attempt to connect a single drone with timeout."""
        await log_message(f"Connecting {drone_id} to {drone_ip}")
        loop = asyncio.get_running_loop()
        try:
            vehicle = await asyncio.wait_for(
                loop.run_in_executor(
                    None, functools.partial(connect, drone_ip, wait_ready=True)
                ),
                timeout=10,
            )
            vehicle.id = drone_id

            def status_text_listener(self, name, message):
                text = getattr(message, "text", "")
                if isinstance(text, bytes):
                    text = text.decode("utf-8", errors="ignore")
                text = text.rstrip("\x00")
                asyncio.run_coroutine_threadsafe(
                    log_message(f"{self.id}: {text}"), loop
                )

            vehicle.add_message_listener("STATUSTEXT", status_text_listener)

            vehicles[drone_id] = vehicle
            connected.append(drone_id)
            await log_message(f"{drone_id} connected successfully at {drone_ip}.")
        except Exception as e:
            failed.append(drone_id)
            await log_message(f"Failed to connect {drone_id}: {e}")

    tasks = [connect_drone(drone_id, ip) for drone_id, ip in drones.items()]
    gather_task = asyncio.gather(*tasks)

    async def keepalive():
        """Send periodic messages so the client doesn't timeout."""
        while not gather_task.done():
            try:
                await websocket.send(json.dumps({
                    "status": "connecting",
                    "message": "Attempting to connect to drones...",
                }))
            except websockets.exceptions.ConnectionClosed:
                break
            await asyncio.sleep(1)

    heartbeat = asyncio.create_task(keepalive())
    await gather_task
    heartbeat.cancel()
    try:
        await heartbeat
    except asyncio.CancelledError:
        pass

    # ✅ Debug print the final stored vehicles dictionary
    await log_message(f"🔍 DEBUG: Vehicles Stored → {vehicles}")

    status = "success" if not failed else "error" if not connected else "partial"

    await websocket.send(json.dumps({
        "status": status,
        "connected": connected,
        "failed": failed,
    }))

    # ✅ Start telemetry updates immediately after connecting if at least one drone connected
    if connected:
        global telemetry_task
        if telemetry_task and not telemetry_task.done():
            telemetry_task.cancel()
            try:
                await telemetry_task
            except asyncio.CancelledError:
                pass
        telemetry_task = asyncio.create_task(send_telemetry())



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
    global stop_operations_event, drone_command_data, drone_thread


    if not vehicles:
        await log_message("🚨 No drones connected! Cannot start operations.")
        return

    if not landing_complete_event.is_set():
        await log_message("Cannot start; landing still in progress.")
        return
    landing_complete_event.clear()

    await log_message("🚀 Starting drone operations...")

    stop_operations_event.clear()

    # Restart telemetry if it was previously stopped
    global telemetry_task
    if not telemetry_task or telemetry_task.done():
        telemetry_task = asyncio.create_task(send_telemetry())

    # ✅ Extract parameters from WebSocket message
    takeoff_altitude = params.get("takeoff_altitude", 3.0)
    initial_position_speed = params.get("initial_position_speed", 3.0)
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
        "initial_position_speed": initial_position_speed,
    })

    # ✅ Only pass the list of `Vehicle` objects, NOT tuples
    drone_list = list(vehicles.values())

    def run_operations():
        try:
            operate_drones(drone_list, takeoff_altitude, target_altitude, drone_command_data)
        finally:
            landing_complete_event.set()

    drone_thread = threading.Thread(target=run_operations, daemon=True)
    drone_thread.start()






async def handle_stop_operations():
    """
    Handles the 'stop_operations' command to land all drones.
    """
    global stop_operations_event, telemetry_task, vehicles, drone_thread



    stop_operations_event.set()

    # Attempt to clean up the operations thread without blocking this coroutine.
    # Joining in an executor allows the event loop to continue immediately,
    # while still ensuring that resources are released once the thread exits.
    if drone_thread:
        thread_to_join = drone_thread
        drone_thread = None
        loop = asyncio.get_running_loop()
        loop.run_in_executor(None, thread_to_join.join)

    if not landing_complete_event.is_set():
        loop = asyncio.get_running_loop()
        vehicle_items = list(vehicles.items())
        landing_tasks = [
            loop.run_in_executor(None, land, vehicle, drone_id)
            for drone_id, vehicle in vehicle_items
        ]
        results = await asyncio.gather(*landing_tasks, return_exceptions=True)
        for (drone_id, _), result in zip(vehicle_items, results):
            if isinstance(result, Exception):
                await log_message(f"Error landing vehicle {drone_id}: {result}")
    landing_complete_event.set()



    if telemetry_task and not telemetry_task.done():
        telemetry_task.cancel()
        try:
            await telemetry_task
        except asyncio.CancelledError:
            pass
    telemetry_task = None

    landing_message = json.dumps({"command": "landing_complete"})
    for client in list(server_log_clients):
        try:
            await client.send(landing_message)
        except websockets.exceptions.ConnectionClosed:
            server_log_clients.remove(client)

    await log_message("🛬 Stop operations signal received! Landing all drones.")


async def handle_disconnect():
    """Explicitly close all vehicle connections and clear state."""
    global vehicles

    await handle_stop_operations()

    for vehicle in list(vehicles.values()):
        try:
            vehicle.close()
        except Exception as e:
            await log_message(f"Error closing vehicle {getattr(vehicle, 'id', 'unknown')}: {e}")
    vehicles.clear()

    await log_message("🔌 All drones disconnected.")


async def log_message(message):
    """
    Logs a message to the console and broadcasts it to all subscribed WebSocket clients.
    """
    logger.info(message)

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
    loop = asyncio.get_running_loop()
    handler = WebsocketLogHandler(loop)
    logging.getLogger("drone_operations").addHandler(handler)
    logging.getLogger("error_handler").addHandler(handler)
    logging.getLogger("autopilot").addHandler(handler)
    logging.getLogger("dronekit").addHandler(handler)

    server = await websockets.serve(handle_client, "0.0.0.0", 5000)
    await log_message("WebSocket server running at ws://0.0.0.0:5000")
    await server.wait_closed()

if __name__ == "__main__":
    asyncio.run(main())
