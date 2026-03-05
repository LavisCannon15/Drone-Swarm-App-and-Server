#drone_operations.py
from dronekit import VehicleMode
import time
import threading
import logging
import math
import itertools
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
    calculate_triangle_positions,
    swap_triangle_positions,
    rotate_triangle_around_center,
    calculate_revolving_positions,
    calculate_rotation_params,
)


logger = logging.getLogger(__name__)
logger.propagate = True
logger.setLevel(logging.INFO)

# ``websocket_data_stream`` is a shared dictionary between the WebSocket
# server and this module.  Fields such as ``latitude``, ``longitude`` and
# other telemetry values are owned by the WebSocket server thread and are
# read-only here.  Mode flags (``orbit_around_user``, ``swap_positions`` and
# ``rotate_triangle_formation``) may be cleared by this module when an
# operation finishes.  Any writes to these flags must hold
# ``websocket_lock`` to avoid concurrent updates.
websocket_lock = threading.Lock()


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
    stationary_speed_threshold=0.35,
    moving_speed_threshold=0.8,
    movement_distance_threshold_m=1.5,
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
        stationary_speed_threshold (float): Speed threshold to enter stationary state.
        moving_speed_threshold (float): Speed threshold to exit stationary state.
        movement_distance_threshold_m (float): Distance threshold to exit stationary state.

    Returns:
        tuple: (user_orbit_lat, user_orbit_lon, last_known_lat, last_known_lon, is_stationary)
    """
    # Initialize orbit lock center on first sample.
    if last_known_lat is None or last_known_lon is None:
        last_known_lat, last_known_lon = current_lat, current_lon

    distance_from_lock = great_circle(
        (current_lat, current_lon), (last_known_lat, last_known_lon)
    ).meters

    # Use hysteresis (different enter/exit thresholds) plus distance guard to
    # avoid rapid mode flipping from noisy GPS speed values.
    if is_stationary:
        if (
            user_speed > moving_speed_threshold
            and distance_from_lock > movement_distance_threshold_m
        ):
            logger.info("User resumed movement.")
            is_stationary = False
            last_known_lat, last_known_lon = current_lat, current_lon
    else:
        if user_speed < stationary_speed_threshold:
            last_known_lat, last_known_lon = current_lat, current_lon
            logger.info("User is stationary. Locking orbit center.")
            is_stationary = True
        else:
            # Keep a fresh reference while user is moving.
            last_known_lat, last_known_lon = current_lat, current_lon

    # Use last known position if stationary, otherwise live GPS data
    user_orbit_lat = last_known_lat if is_stationary else current_lat
    user_orbit_lon = last_known_lon if is_stationary else current_lon

    return user_orbit_lat, user_orbit_lon, last_known_lat, last_known_lon, is_stationary


def _required_radius_for_spacing(min_spacing_m, num_drones):
    """Compute minimum orbit radius needed for pairwise spacing on a circle."""
    if num_drones <= 1:
        return 0.0
    denominator = 2.0 * math.sin(math.pi / num_drones)
    if denominator <= 0.0:
        return 0.0
    return min_spacing_m / denominator


def _minimum_pairwise_distance_points(points):
    if len(points) < 2:
        return float("inf")
    minimum = float("inf")
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            minimum = min(minimum, great_circle(points[i], points[j]).meters)
    return minimum


def _minimum_pairwise_distance_drones(drones):
    positions = []
    for drone in drones:
        try:
            pos = drone.location.global_relative_frame
            if pos and pos.lat is not None and pos.lon is not None:
                positions.append((pos.lat, pos.lon))
        except Exception:
            continue
    return _minimum_pairwise_distance_points(positions)


def _average_distance_to_center_drones(drones, center_lat, center_lon):
    distances = []
    for drone in drones:
        try:
            pos = drone.location.global_relative_frame
            if pos and pos.lat is not None and pos.lon is not None:
                distances.append(
                    great_circle((center_lat, center_lon), (pos.lat, pos.lon)).meters
                )
        except Exception:
            continue
    if not distances:
        return float("inf")
    return sum(distances) / len(distances)


def _build_orbit_assignment(drones, orbit_points):
    """
    Build a stable mapping from drone index -> orbit point index.
    Keeps each drone on a consistent lane to avoid crossover during orbit entry.
    """
    n = min(len(drones), len(orbit_points))
    if n <= 1:
        return list(range(n))

    drone_positions = []
    for idx in range(n):
        try:
            pos = drones[idx].location.global_relative_frame
            if pos and pos.lat is not None and pos.lon is not None:
                drone_positions.append((pos.lat, pos.lon))
            else:
                drone_positions.append(orbit_points[idx])
        except Exception:
            drone_positions.append(orbit_points[idx])

    indices = list(range(n))
    if n <= 7:
        best_perm = None
        best_cost = float("inf")
        for perm in itertools.permutations(indices):
            total_cost = 0.0
            for i in indices:
                total_cost += great_circle(
                    drone_positions[i], orbit_points[perm[i]]
                ).meters
            if total_cost < best_cost:
                best_cost = total_cost
                best_perm = perm
        return list(best_perm) if best_perm is not None else indices

    # Fallback greedy assignment for larger swarms.
    remaining = set(indices)
    assignment = []
    for i in indices:
        best_idx = min(
            remaining,
            key=lambda p: great_circle(drone_positions[i], orbit_points[p]).meters,
        )
        assignment.append(best_idx)
        remaining.remove(best_idx)
    return assignment


def _apply_assignment(points, assignment):
    if not assignment or len(points) != len(assignment):
        return points
    return [points[idx] for idx in assignment]


def _bearing_from_center_deg(center_lat, center_lon, point_lat, point_lon):
    phi1 = math.radians(center_lat)
    phi2 = math.radians(point_lat)
    dlambda = math.radians(point_lon - center_lon)

    y = math.sin(dlambda) * math.cos(phi2)
    x = (
        math.cos(phi1) * math.sin(phi2)
        - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
    )
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def _circular_mean_deg(angles_deg):
    if not angles_deg:
        return None

    sin_sum = sum(math.sin(math.radians(angle)) for angle in angles_deg)
    cos_sum = sum(math.cos(math.radians(angle)) for angle in angles_deg)
    if abs(sin_sum) < 1e-9 and abs(cos_sum) < 1e-9:
        return None

    return (math.degrees(math.atan2(sin_sum, cos_sum)) + 360.0) % 360.0


def _measure_formation_phase_deg(drones, center_lat, center_lon, slot_count):
    if slot_count <= 0:
        return None

    phase_samples = []
    for drone in drones:
        try:
            pos = drone.location.global_relative_frame
            if pos and pos.lat is not None and pos.lon is not None:
                bearing = _bearing_from_center_deg(center_lat, center_lon, pos.lat, pos.lon)
                phase_samples.append((bearing * slot_count) % 360.0)
        except Exception:
            continue

    phase_mean = _circular_mean_deg(phase_samples)
    if phase_mean is None:
        return None

    return (phase_mean / slot_count) % 360.0


def _wrap_phase_error_deg(error_deg, period_deg):
    half_period = period_deg / 2.0
    return (error_deg + half_period) % period_deg - half_period




def operate_drones(drones, takeoff_altitude, target_altitude, websocket_data_stream):
    """
    Coordinate drone movements based on a shared ``websocket_data_stream``.

    The data stream is a dictionary updated by the WebSocket server thread and
    read by this function.  Telemetry fields (``latitude``, ``longitude``,
    ``speed`` and related distance/speed parameters) are written by the server
    and treated as read-only here.  Mode flags (``orbit_around_user``,
    ``swap_positions`` and ``rotate_triangle_formation``) may be cleared by
    this function when their operations complete.  All writes to those flags are
    protected by ``websocket_lock``.
    """
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
    revolve_offset_distance = websocket_data_stream.get("revolve_offset_distance", 4.0)
    initial_orbit_around_user = websocket_data_stream.get("orbit_around_user", False)
    initial_swap_positions = websocket_data_stream.get("swap_positions", False)
    initial_rotate_triangle_formation = websocket_data_stream.get(
        "rotate_triangle_formation", False
    )

    initial_position_radius = offset_distance
    if (
        initial_orbit_around_user
        or initial_swap_positions
        or initial_rotate_triangle_formation
    ):
        initial_position_radius = revolve_offset_distance

    logger.info("Phase: formation positioning start")
    # Compute triangle formation based on initial user location
    triangle_positions = calculate_triangle_positions(
        current_lat, current_lon, initial_position_radius
    )
    move_to_initial_positions(drones, triangle_positions, initial_position_speed)
    wait_for_drones_to_reach_positions(drones, triangle_positions, stop_operations_event)
    logger.info("Phase: formation positioning complete")
    
    time.sleep(4)

    previous_time = time.time()
    counter = 0

    angle_offset = 0
    last_known_lat, last_known_lon = None, None  # Initialize last known coordinates
    is_stationary = False  # Initialize stationary flag
    control_loop_period = 0.2  # 5 Hz target update loop
    orbit_assignment = None
    orbit_phase_integral = 0.0
    follow_assignment = None
    last_effective_mode = None
    last_spacing_log_at = 0.0

    logger.info("Phase: active operation start")
    try:
        # Main loop: move drones based on real-time user movement
        while not stop_operations_event.is_set():
            loop_started_at = time.time()
            # Retrieve latest real-time data from WebSocket
            current_lat = websocket_data_stream.get("latitude", 0.0)
            current_lon = websocket_data_stream.get("longitude", 0.0)
            kalman_user_speed = websocket_data_stream.get("speed", 0.0)
            offset_distance = websocket_data_stream.get("offset_distance", 4.0)
            orbit_around_user = websocket_data_stream.get("orbit_around_user", False)
            swap_positions = websocket_data_stream.get("swap_positions", False)
            rotate_triangle_formation = websocket_data_stream.get("rotate_triangle_formation", False)
            revolve_speed = websocket_data_stream.get("revolve_speed", 2.0)  # m/s
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
            current_time = time.time()
            elapsed_time = max(0.0, current_time - previous_time)
            previous_time = current_time

            requested_mode = "follow"
            if orbit_around_user:
                requested_mode = "orbit"
            elif rotate_triangle_formation:
                requested_mode = "rotate_triangle"
            elif swap_positions:
                requested_mode = "swap_positions"

            # Orbit mode is intentionally active only when the user is stationary.
            effective_mode = (
                "follow"
                if requested_mode == "orbit" and not is_stationary
                else requested_mode
            )
            entering_orbit = effective_mode == "orbit" and last_effective_mode != "orbit"
            if effective_mode != last_effective_mode:
                logger.info(
                    "MODE=%s | stationary=%s",
                    effective_mode,
                    is_stationary,
                )
                if effective_mode != "orbit":
                    orbit_assignment = None
                    orbit_phase_integral = 0.0
                if effective_mode != "follow":
                    follow_assignment = None
                last_effective_mode = effective_mode

            if effective_mode == "orbit":
                swap_positions = False
                rotate_triangle_formation = False
                with websocket_lock:
                    websocket_data_stream["swap_positions"] = False
                    websocket_data_stream["rotate_triangle_formation"] = False

                requested_spacing = max(float(offset_distance), 4.0)
                safe_radius = max(0.1, float(revolve_offset_distance))
                minimum_radius = _required_radius_for_spacing(
                    requested_spacing, len(drones)
                )
                safe_radius = max(safe_radius, minimum_radius)

                requested_speed = max(0.0, float(revolve_speed))
                max_angular_rate = 0.20  # rad/s safety cap for stable tracking
                safe_speed = min(
                    requested_speed,
                    max(0.3, safe_radius * max_angular_rate),
                )

                phase_period = 360.0 / max(len(drones), 1)
                measured_phase = _measure_formation_phase_deg(
                    drones,
                    user_orbit_lat,
                    user_orbit_lon,
                    len(drones),
                )
                live_orbit_radius = _average_distance_to_center_drones(
                    drones, user_orbit_lat, user_orbit_lon
                )

                if entering_orbit and measured_phase is not None:
                    angle_offset = measured_phase
                    orbit_phase_integral = 0.0
                    logger.info(
                        "Orbit phase lock | phase=%.1f | offset_live=%.2fm | offset_set=%.2fm",
                        measured_phase % phase_period,
                        live_orbit_radius,
                        safe_radius,
                    )

                _, cycle_time = calculate_rotation_params(safe_radius, max(safe_speed, 0.01))
                if safe_speed > 0:
                    angle_offset = (angle_offset + (360 / cycle_time) * elapsed_time) % 360
                phase_error = 0.0
                if measured_phase is not None:
                    phase_error = _wrap_phase_error_deg(
                        measured_phase - angle_offset,
                        phase_period,
                    )
                    orbit_phase_integral += phase_error * elapsed_time
                    orbit_phase_integral = max(-20.0, min(20.0, orbit_phase_integral))
                else:
                    orbit_phase_integral = 0.0

                phase_correction = max(
                    -8.0,
                    min(8.0, 0.45 * phase_error + 0.08 * orbit_phase_integral),
                )
                command_phase = (angle_offset + phase_correction) % 360.0

                triangle_positions = calculate_revolving_positions(
                    user_orbit_lat,
                    user_orbit_lon,
                    safe_radius,
                    len(drones),
                    command_phase,
                )

                if entering_orbit or orbit_assignment is None or len(orbit_assignment) != len(drones):
                    orbit_assignment = _build_orbit_assignment(
                        drones, triangle_positions
                    )
                triangle_positions = _apply_assignment(
                    triangle_positions, orbit_assignment
                )
                target_spacing = _minimum_pairwise_distance_points(triangle_positions)
                live_spacing = _minimum_pairwise_distance_drones(drones)

                command_speed = max(safe_speed, 0.3)
                move_to_positions(
                    drones,
                    triangle_positions,
                    command_speed,
                    target_altitude,
                    mode_label="orbit",
                )
                if current_time - last_spacing_log_at >= 1.0:
                    logger.info(
                        "SPACING mode=orbit live=%.2fm target=%.2fm offset_set=%.2fm offset_cmd=%.2fm live_offset=%.2fm speed_set=%.2f phase_meas=%.1f phase_cmd=%.1f phase_err=%.1f",
                        live_spacing,
                        target_spacing,
                        safe_radius,
                        safe_radius,
                        live_orbit_radius,
                        command_speed,
                        measured_phase % phase_period if measured_phase is not None else float("nan"),
                        command_phase % phase_period,
                        phase_error,
                    )
                    last_spacing_log_at = current_time

                logger.debug(
                    "Orbit | center=(%.7f, %.7f) | cycle=%.2fs | speed=%.2f m/s | phase_ref=%.1f | phase_cmd=%.1f | phase_err=%.1f | radius=%.2f | target_spacing=%.2f",
                    user_orbit_lat,
                    user_orbit_lon,
                    cycle_time,
                    command_speed,
                    angle_offset,
                    command_phase,
                    phase_error,
                    safe_radius,
                    target_spacing,
                )

            elif effective_mode == "rotate_triangle":
                orbit_around_user = False
                swap_positions = False
                with websocket_lock:
                    websocket_data_stream["orbit_around_user"] = False
                    websocket_data_stream["swap_positions"] = False

                # Calculate linear speed and cycle time based on current parameters
                requested_spacing = max(float(offset_distance), 4.0)
                safe_radius = max(0.1, float(revolve_offset_distance))
                safe_radius = max(
                    safe_radius,
                    _required_radius_for_spacing(requested_spacing, len(drones)),
                )
                safe_speed = max(0.0, float(revolve_speed))
                linear_speed, cycle_time = calculate_rotation_params(
                    safe_radius, max(safe_speed, 0.01)
                )

                # Adjust the angle_offset using the cycle time (degrees per second)
                if safe_speed > 0:
                    angle_offset = (angle_offset + (360 / cycle_time) * elapsed_time) % 360

                triangle_positions = calculate_triangle_positions(
                    user_orbit_lat, user_orbit_lon, safe_radius
                )
                triangle_positions = rotate_triangle_around_center(
                    triangle_positions, angle_offset
                )

                move_to_positions(
                    drones,
                    triangle_positions,
                    max(linear_speed, 0.3),
                    target_altitude,
                    mode_label="rotate_triangle",
                )

                logger.debug(
                    f"Cycle Time: {cycle_time:.2f} seconds, Speed: {linear_speed:.2f} m/s"
                )

            elif effective_mode == "swap_positions":
                orbit_around_user = False
                rotate_triangle_formation = False
                with websocket_lock:
                    websocket_data_stream["orbit_around_user"] = False
                    websocket_data_stream["rotate_triangle_formation"] = False

                requested_spacing = max(float(offset_distance), 4.0)
                safe_radius = max(0.1, float(revolve_offset_distance))
                safe_radius = max(
                    safe_radius,
                    _required_radius_for_spacing(requested_spacing, len(drones)),
                )
                triangle_positions = calculate_triangle_positions(
                    user_orbit_lat,
                    user_orbit_lon,
                    safe_radius,
                )
                triangle_positions = swap_triangle_positions(triangle_positions, counter)

                # Increment the counter and reset if necessary
                counter += 1
                if counter > 2:  # Reset after maximum number of swaps
                    counter = 0

                move_to_positions(
                    drones,
                    triangle_positions,
                    max(float(swap_position_speed), 0.3),
                    target_altitude,
                    mode_label="swap_positions",
                )

                wait_for_drones_to_reach_positions(drones, triangle_positions, stop_operations_event)

                # Swap is a one-time action unless re-triggered
                swap_positions = False
                with websocket_lock:
                    websocket_data_stream["swap_positions"] = False

            else:
                # Calculate and adjust positions for triangular formation
                requested_spacing = max(float(offset_distance), 4.0)
                follow_set_radius = max(0.1, float(offset_distance))
                follow_set_radius = max(
                    follow_set_radius,
                    _required_radius_for_spacing(requested_spacing, len(drones)),
                )
                follow_radius = follow_set_radius
                triangle_positions = calculate_triangle_positions(
                    user_orbit_lat, user_orbit_lon, follow_radius
                )
                if follow_assignment is None or len(follow_assignment) != len(drones):
                    follow_assignment = _build_orbit_assignment(
                        drones, triangle_positions
                    )
                triangle_positions = _apply_assignment(
                    triangle_positions, follow_assignment
                )
                target_spacing = _minimum_pairwise_distance_points(triangle_positions)

                # If live spacing collapses in simulation, widen triangle and slow.
                live_spacing = _minimum_pairwise_distance_drones(drones)
                follow_speed = max(float(kalman_user_speed), 0.3)
                if live_spacing < max(3.0, 0.8 * target_spacing):
                    follow_radius += 0.7
                    triangle_positions = calculate_triangle_positions(
                        user_orbit_lat, user_orbit_lon, follow_radius
                    )
                    triangle_positions = _apply_assignment(
                        triangle_positions, follow_assignment
                    )
                    follow_speed = min(max(follow_speed, 0.6), 1.2)
                    logger.warning(
                        "Follow deformation: live=%.2fm target=%.2fm. Expanding radius to %.2fm.",
                        live_spacing,
                        target_spacing,
                        follow_radius,
                    )

                #move_to_positions_velocity(drones, triangle_positions, kalman_user_speed, target_altitude)
                move_to_positions(
                    drones,
                    triangle_positions,
                    follow_speed,
                    target_altitude,
                    mode_label="follow",
                )
                if current_time - last_spacing_log_at >= 1.0:
                    logger.info(
                        "SPACING mode=follow live=%.2fm target=%.2fm offset_set=%.2fm offset_cmd=%.2fm speed_set=%.2f",
                        live_spacing,
                        target_spacing,
                        follow_set_radius,
                        follow_radius,
                        follow_speed,
                    )
                    last_spacing_log_at = current_time

            # Monitor drones for issues (battery, GPS, etc.)
            should_stop = monitor_drones(
                drones,
                low_battery_threshold=20,
                stop_operations_event=stop_operations_event,
            )
            if should_stop:
                break  # Stop operations if monitoring indicates issues

            loop_elapsed = time.time() - loop_started_at
            sleep_time = control_loop_period - loop_elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

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
