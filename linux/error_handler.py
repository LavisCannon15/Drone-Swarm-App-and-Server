import logging


logger = logging.getLogger(__name__)
logger.propagate = False


class LowBatteryError(Exception):
    """Exception raised for low battery issues."""
    pass


class DroneCrashError(Exception):
    """Exception raised when a drone crashes or is not flying."""
    pass


class GPSLossError(Exception):
    """Exception raised when a drone loses GPS signal."""
    pass


def handle_drone_exceptions(e, stop_operations_event):
    if isinstance(e, KeyboardInterrupt):
        logger.info("KeyboardInterrupt detected, stopping drone operations.")
    elif isinstance(e, TimeoutError):
        logger.error("TimeoutError: Communication with the drone timed out. Initiating landing sequence.")
    elif isinstance(e, LowBatteryError):
        logger.error(f"LowBatteryError: {e}. Initiating landing sequence.")
    elif isinstance(e, DroneCrashError):
        logger.error(f"DroneCrashError: {e}. Initiating landing sequence.")
    elif isinstance(e, GPSLossError):
        logger.error(f"GPSLossError: {e}. Initiating landing sequence.")
    elif isinstance(e, ValueError):
        logger.error(f"ValueError: {e}. Initiating landing sequence for safety.")
    else:
        logger.error(f"Unexpected error: {e}. Initiating landing sequence.")

    # Ensure the stop_operations_event is set for any handled exception
    stop_operations_event.set()


def check_battery(drone, low_battery_threshold, stop_operations_event):
    """Check if the drone's battery is below the threshold."""
    if drone.battery.level < low_battery_threshold:
        logger.warning(f"{drone.id}: Battery low at {drone.battery.level}%")
        raise LowBatteryError(f"Drone {drone.id} battery level is too low: {drone.battery.level}.")


def check_drone_status(drone, stop_operations_event):
    """Check if the drone is flying and listen for critical messages."""
    # Register a message listener for critical messages
    drone.add_message_listener('CRITICAL', handle_critical_message)

    vertical_velocity = drone.velocity[2]  # Vertical velocity (m/s, negative means descending)
    altitude = drone.location.global_relative_frame.alt  # Current altitude (m)
    attitude_error = abs(drone.attitude.roll) + abs(drone.attitude.pitch)  # Combined roll and pitch error

    # Check for potential crash conditions
    if vertical_velocity < -5 and altitude < 1:
        logger.warning(f"{drone.id}: Possible crash detected (v={vertical_velocity}, alt={altitude})")
        raise DroneCrashError(f"Drone {drone.id} has crashed or is not in a flying state.")
    if attitude_error > 30:  # Threshold for angle error
        logger.warning(f"{drone.id}: Excessive attitude error {attitude_error} degrees")
        raise DroneCrashError(f"Drone {drone.id} has excessive attitude error: {attitude_error} degrees.")
    if not drone.armed:
        logger.warning(f"{drone.id}: Drone unexpectedly disarmed")
        raise DroneCrashError(f"Drone {drone.id} unexpectedly disarmed.")


def handle_critical_message(message):
    """Handle critical messages from the drone."""
    if 'CRASH' in message:
        raise DroneCrashError(f"Drone reported a crash condition: {message}")
    # You can handle other messages or log them as needed
    logger.warning(f"Received critical message from drone: {message}")


def check_gps(drone, stop_operations_event):
    """Check if the drone has a valid GPS fix."""
    gps_info = drone.gps_0

    # Check the GPS fix type
    if gps_info.fix_type < 2:  # No fix or 2D fix
        logger.warning(f"{drone.id}: GPS fix lost ({gps_info.fix_type})")
        raise GPSLossError(f"Drone {drone.id} has lost GPS signal or has insufficient GPS accuracy. Fix type: {gps_info.fix_type}.")

    # Optionally check for number of satellites visible for more robustness
    if gps_info.satellites_visible < 4:  # Less than 4 satellites is generally considered unreliable
        logger.warning(f"{drone.id}: Low satellite count {gps_info.satellites_visible}")
        raise GPSLossError(f"Drone {drone.id} has insufficient satellite visibility: {gps_info.satellites_visible} satellites.")


def monitor_drones(drones, low_battery_threshold, stop_operations_event):
    """Monitor all drones for potential issues.

    Returns:
        bool: ``True`` if any monitoring check fails, otherwise ``False``.
    """
    for drone in drones:
        try:
            check_battery(drone, low_battery_threshold, stop_operations_event)
            check_drone_status(drone, stop_operations_event)
            check_gps(drone, stop_operations_event)
        except Exception as e:
            handle_drone_exceptions(e, stop_operations_event)
            return True

    return False
