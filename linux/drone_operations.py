#drone_operations.py
from dronekit import VehicleMode
import time
import threading
import logging
from concurrent.futures import ThreadPoolExecutor
from global_vars import stop_operations_event
from geopy.distance import great_circle  # Ensure you have geopy installed
from error_handler import monitor_drones, handle_drone_exceptions
#from simulated_sensors import  simulate_user_movement
from drone_movements import (
    move_to_positions,
    move_to_initial_positions,
    move_to_positions_velocity,
    move_to_positions_with_ned,
    send_ned_velocity,
)
from position_calculations import (
    calculate_triangle_positions, swap_triangle_positions, rotate_triangle_around_center,
    calculate_revolving_positions, calculate_rotation_params, ensure_equal_distance,
    ensure_equal_distance_from_user, calculate_rotation_params2
)


logger = logging.getLogger(__name__)
logger.propagate = False


def arm_and_takeoff(vehicle, target_altitude, drone_id, stop_operations_event):
    """Arm the vehicle and take off, relying on ArduPilot for state checks."""

    logger.info(f"{drone_id}: Changing to GUIDED mode...")
    try:
        vehicle.mode = VehicleMode("GUIDED")
    except Exception as e:
        logger.error(f"{drone_id}: Failed to set GUIDED mode: {e}")
        return

    # Wait until the vehicle is in GUIDED mode
    last_guided_log = 0
    while vehicle.mode.name != "GUIDED":
        if stop_operations_event.is_set():
            logger.warning(f"{drone_id}: Stop signal received. Aborting mode change.")
            return
        current_time = time.time()
        if current_time - last_guided_log >= 5:
            logger.info(f"{drone_id}: Waiting for GUIDED mode...")
            last_guided_log = current_time
        time.sleep(1)

    logger.info(f"{drone_id}: Waiting for vehicle to be ready to arm...")
    last_armable_log = 0
    while not vehicle.is_armable:
        if stop_operations_event.is_set():
            logger.warning(f"{drone_id}: Stop signal received. Aborting arming process.")
            return
        current_time = time.time()
        if current_time - last_armable_log >= 5:
            logger.info(f"{drone_id}: Vehicle not armable yet. Waiting...")
            last_armable_log = current_time
        time.sleep(1)

    logger.info(f"{drone_id}: Arming...")
    try:
        vehicle.armed = True
    except Exception as e:
        logger.error(f"{drone_id}: Arming failed: {e}")
        return

    last_arming_log = 0
    while not vehicle.armed:
        if stop_operations_event.is_set():
            logger.warning(f"{drone_id}: Stop signal received. Aborting arming.")
            return
        current_time = time.time()
        if current_time - last_arming_log >= 5:
            logger.info(f"{drone_id}: Waiting for arming...")
            last_arming_log = current_time
        time.sleep(1)

    logger.info(f"{drone_id}: Taking off to {target_altitude} meters...")
    try:
        vehicle.simple_takeoff(target_altitude)
    except Exception as e:
        logger.error(f"{drone_id}: Takeoff failed: {e}")
        return

    while True:
        if stop_operations_event.is_set():
            logger.warning(f"{drone_id}: Stop signal received. Aborting takeoff.")
            return

        altitude = vehicle.location.global_relative_frame.alt
        logger.debug(f"{drone_id}: Altitude: {altitude:.2f} meters")

        # Exit the loop when the target altitude is reached
        if altitude >= target_altitude * 0.95:
            logger.info(f"{drone_id}: Reached target altitude.")
            break

        time.sleep(1)


def _hold_position_until_stopped(vehicle, mode_mapping, drone_id):
    """Ensure the vehicle stays in place until its velocity drops below a threshold."""
    try:
        while vehicle.velocity and any(abs(v) > 0.1 for v in vehicle.velocity):
            if "BRAKE" not in mode_mapping:
                try:
                    send_ned_velocity(vehicle, 0, 0, 0)
                except Exception as e:
                    logger.warning(f"{drone_id}: Failed to send hold position command: {e}")
            time.sleep(0.5)
    except Exception as e:
        logger.warning(f"{drone_id}: Error while holding position: {e}")


def land(vehicle, drone_id):
    logger.info(f"{drone_id}: Stopping and landing…")
    mode_mapping = {}
    try:
        mode_mapping = vehicle.mode_mapping()
    except Exception:
        pass

    if "BRAKE" in mode_mapping:
        vehicle.mode = VehicleMode("BRAKE")
    else:
        logger.info(f"{drone_id}: BRAKE mode not supported, holding position with zero velocity.")
        try:
            send_ned_velocity(vehicle, 0, 0, 0)
        except Exception as e:
            logger.warning(f"{drone_id}: Failed to send hold position command: {e}")

    threading.Thread(
        target=_hold_position_until_stopped,
        args=(vehicle, mode_mapping, drone_id),
        daemon=True,
    ).start()
    vehicle.mode = VehicleMode("LAND")


def wait_for_drones_to_reach_positions(drones, triangle_positions, stop_operations_event):
    """
    Waits for all drones to reach their specified positions in a triangle formation.

    Args:
        drones: A list of drone objects.
        triangle_positions: A list of tuples representing the target positions for each drone.
        stop_operations_event: An event object to signal a graceful shutdown.
    """
    for i, drone in enumerate(drones):
        target_position = triangle_positions[i]
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Wait until the drone reaches its target position
        while True:
            if stop_operations_event.is_set():
                logger.warning(f"{drone_id}: Stop signal received. Aborting movement.")
                break
            current_position = (drone.location.global_relative_frame.lat, drone.location.global_relative_frame.lon)
            distance_to_target = great_circle(current_position, target_position).meters
            #logger.debug(f"{drone_id}: Distance to target: {distance_to_target:.2f} meters")

            # Check if the drone has reached its target position with a tolerance (e.g., 1 meter)
            if distance_to_target < 1:
                logger.info(f"{drone_id}: Reached target position.")
                break

            time.sleep(0.5)  # Adjust the sleep time as needed



def determine_user_coordinates(
    current_lat,
    current_lon,
    user_speed,
    last_known_lat=None,
    last_known_lon=None,
    is_stationary=False,
    stationary_speed_threshold=0.5,
):
    """
    Determine the user's coordinates based on movement.

    Args:
        current_lat (float): Current latitude of the user.
        current_lon (float): Current longitude of the user.
        user_speed (float): Current speed of the user.
        last_known_lat (float): Last known latitude when the user was stationary.
        last_known_lon (float): Last known longitude when the user was stationary.
        is_stationary (bool): Whether the user was previously stationary.
        stationary_speed_threshold (float): Speed threshold to determine if the user is stationary.

    Returns:
        tuple: (user_orbit_lat, user_orbit_lon, last_known_lat, last_known_lon, is_stationary)
    """
    if user_speed < stationary_speed_threshold:  # User is stationary
        if not is_stationary:
            # Cache the current position
            last_known_lat, last_known_lon = current_lat, current_lon
            logger.info("User is stationary. Caching last known GPS position.")
            is_stationary = True
    else:
        if is_stationary:
            logger.info("User resumed movement")
        is_stationary = False  # User is moving

    # Use last known position if stationary, otherwise live GPS data
    user_orbit_lat = last_known_lat if is_stationary else current_lat
    user_orbit_lon = last_known_lon if is_stationary else current_lon

    return user_orbit_lat, user_orbit_lon, last_known_lat, last_known_lon, is_stationary




def operate_drones(drones, takeoff_altitude, target_altitude, websocket_data_stream):
    global stop_operations_event  # Use the global stop flag

    # Arm and take off each drone with staggered altitudes
    threads = []
    stagger_step = 1  # Altitude increment for each drone
    base_altitude = takeoff_altitude  # Starting altitude for the first drone

    logger.info("Phase: takeoff start")
    for idx, drone in enumerate(drones):
        drone_id = drone.id if hasattr(drone, 'id') else f"Drone {idx+1}"
        staggered_altitude = base_altitude + (idx * stagger_step)
        
        thread = threading.Thread(
            target=arm_and_takeoff, 
            args=(drone, staggered_altitude, drone_id, stop_operations_event)
        )
        thread.start()
        threads.append(thread)

    # Wait for all arming and takeoff threads to finish
    for thread in threads:
        thread.join()
    logger.info("Phase: takeoff complete")

    # Allow a moment for all drones to stabilize after the takeoff command

    logger.info("Moving to positions")
    initial_position_speed = websocket_data_stream.get("initial_position_speed", 3.0)

    # Read initial user location from WebSocket data stream
    current_lat = websocket_data_stream.get("latitude", 0.0)
    current_lon = websocket_data_stream.get("longitude", 0.0)
    offset_distance = websocket_data_stream.get("offset_distance", 3.0)

    logger.info("Phase: formation positioning start")
    # Compute triangle formation based on initial user location
    triangle_positions = calculate_triangle_positions(current_lat, current_lon, offset_distance)
    move_to_initial_positions(drones, triangle_positions, initial_position_speed)
    wait_for_drones_to_reach_positions(drones, triangle_positions, stop_operations_event)
    logger.info("Phase: formation positioning complete")
    
    time.sleep(4)

    previous_time = time.time()
    counter = 0

    angle_offset = 0
    last_known_lat, last_known_lon = None, None  # Initialize last known coordinates
    is_stationary = False  # Initialize stationary flag

    logger.info("Phase: active operation start")
    try:
        # Main loop: move drones based on real-time user movement
        while not stop_operations_event.is_set():
            # Retrieve latest real-time data from WebSocket
            current_lat = websocket_data_stream.get("latitude", 0.0)
            current_lon = websocket_data_stream.get("longitude", 0.0)
            kalman_user_speed = websocket_data_stream.get("speed", 0.0)
            offset_distance = websocket_data_stream.get("offset_distance", 4.0)
            orbit_around_user = websocket_data_stream.get("orbit_around_user", False)
            swap_positions = websocket_data_stream.get("swap_positions", False)
            rotate_triangle_formation = websocket_data_stream.get("rotate_triangle_formation", False)
            revolve_speed = websocket_data_stream.get("revolve_speed", 1.0)
            swap_position_speed = websocket_data_stream.get("swap_position_speed", 1.0)
            revolve_offset_distance = websocket_data_stream.get("revolve_offset_distance", 4.0)

            # ✅ Debugging Print Statements
            #print(f"📡 DEBUG: Received WebSocket Data Stream → {websocket_data_stream}")
            #print(f"📍 DEBUG: User Location → Lat: {current_lat}, Lon: {current_lon}, Speed: {kalman_user_speed} m/s")
            #print(f"🔄 DEBUG: Orbit Mode → {orbit_around_user}")
            #print(f"♻️ DEBUG: Swap Positions Mode → {swap_positions}")
            #print(f"🔺 DEBUG: Rotate Triangle Mode → {rotate_triangle_formation}")
            #print(f"🔄 DEBUG: Angle Offset → {angle_offset}")
            #print(f"🚀 DEBUG: Orbit Speed → {revolve_speed} m/s")
            #print(f"🛰️ DEBUG: Orbit Distance → {revolve_offset_distance} meters")

            # Determine user movement and adjust drone positions
            previous_is_stationary = is_stationary
            (
                user_orbit_lat,
                user_orbit_lon,
                last_known_lat,
                last_known_lon,
                is_stationary,
            ) = determine_user_coordinates(
                current_lat,
                current_lon,
                kalman_user_speed,
                last_known_lat,
                last_known_lon,
                previous_is_stationary,
            )

            if is_stationary:
                if orbit_around_user:
                    swap_positions = False
                    rotate_triangle_formation = False

                    current_time = time.time()
                    elapsed_time = current_time - previous_time
                    previous_time = current_time

                    # Calculate speed and cycle time based on current parameters
                    speed, cycle_time = calculate_rotation_params(revolve_offset_distance, revolve_speed)

                    # Adjust the angle_offset based on speed and elapsed time
                    angle_offset += speed * elapsed_time

                    triangle_positions = calculate_revolving_positions(
                        user_orbit_lat, user_orbit_lon, revolve_offset_distance, len(drones), angle_offset)                
                    
                    move_to_positions(drones, triangle_positions, speed, target_altitude)

                    logger.debug(f"Cycle Time: {cycle_time:.2f} seconds, Speed: {speed:.2f} m/s")

            

                elif rotate_triangle_formation:
                    orbit_around_user = False
                    swap_positions = False

                    current_time = time.time()
                    elapsed_time = current_time - previous_time
                    previous_time = current_time

                    # Calculate speed and cycle time based on current parameters
                    speed, cycle_time = calculate_rotation_params(revolve_offset_distance, revolve_speed)

                    # Adjust the angle_offset based on speed and elapsed time
                    angle_offset += speed * elapsed_time

                    triangle_positions = calculate_triangle_positions(user_orbit_lat, user_orbit_lon, revolve_offset_distance)
                    triangle_positions = rotate_triangle_around_center(triangle_positions, angle_offset)

                    move_to_positions(drones, triangle_positions, speed, target_altitude)

                    logger.debug(f"Cycle Time: {cycle_time:.2f} seconds, Speed: {speed:.2f} m/s")

                elif swap_positions:
                    orbit_around_user = False
                    rotate_triangle_formation = False

                    triangle_positions = calculate_triangle_positions(user_orbit_lat, user_orbit_lon, revolve_offset_distance)
                    triangle_positions = swap_triangle_positions(triangle_positions, counter)

                    # Increment the counter and reset if necessary
                    counter += 1
                    if counter > 2:  # Reset after maximum number of swaps
                        counter = 0

                    move_to_positions(drones, triangle_positions, swap_position_speed, target_altitude)

                    wait_for_drones_to_reach_positions(drones, triangle_positions, stop_operations_event)

            else:
                # Calculate and adjust positions for triangular formation
                triangle_positions = calculate_triangle_positions(user_orbit_lat, user_orbit_lon, revolve_offset_distance)
                triangle_positions = ensure_equal_distance(drones, triangle_positions, offset_distance)

                #move_to_positions_velocity(drones, triangle_positions, kalman_user_speed, target_altitude)
                move_to_positions(drones, triangle_positions, kalman_user_speed, target_altitude)

            # Monitor drones for issues (battery, GPS, etc.)
            should_stop = monitor_drones(
                drones,
                low_battery_threshold=20,
                stop_operations_event=stop_operations_event,
            )
            if should_stop:
                break  # Stop operations if monitoring indicates issues

    except (KeyboardInterrupt, TimeoutError, ValueError, Exception) as e:
        handle_drone_exceptions(e, stop_operations_event)

    finally:
        logger.info("Phase: landing start")
        stop_operations_event.set()
        # Ensure that the drones land regardless of the reason for stopping
        with ThreadPoolExecutor() as executor:
            future_to_drone = {
                executor.submit(land, drone, drone.id if hasattr(drone, 'id') else 'Unknown'):
                (drone.id if hasattr(drone, 'id') else 'Unknown')
                for drone in drones
            }
            for future, drone_id in future_to_drone.items():
                try:
                    future.result()
                except Exception as e:
                    logger.error(f"Error during landing of {drone_id}: {e}")

        logger.info("Phase: landing complete")
