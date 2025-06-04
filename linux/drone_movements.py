import math
import time
from dronekit import LocationGlobalRelative
from pymavlink import mavutil

def move_to_positions(drones, triangle_positions,kalman_user_speed, altitude):
    for drone, target_position in zip(drones, triangle_positions):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        #drone.airspeed = kalman_user_speed
        print(f"{drone_id}: Moving to triangle position at {target_position}...")

        drone.simple_goto(LocationGlobalRelative(target_position[0], target_position[1], altitude),kalman_user_speed)

        print(f"{drone_id}: Speed {drone.airspeed:.2f} m/s (Set Speed: {kalman_user_speed:.2f} m/s)")


def move_to_initial_positions(drones, triangle_positions, kalman_user_speed):
    for drone, target_position in zip(drones, triangle_positions):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Use the current drone's altitude to maintain staggered levels
        current_altitude = drone.location.global_relative_frame.alt

        # Move the drone to the target position while preserving its current altitude
        drone.simple_goto(LocationGlobalRelative(target_position[0], target_position[1], current_altitude), kalman_user_speed)

        print(f"{drone_id}: Moving to {target_position} at altitude {current_altitude:.2f} m "
              f"with speed {kalman_user_speed:.2f} m/s.")


"""
Controls drone via mavlink message
def move_to_positions(drones, triangle_positions, altitude):
    for drone, target_position in zip(drones, triangle_positions):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Prepare the target position using LocationGlobalRelative
        target_location = LocationGlobalRelative(target_position[0], target_position[1], altitude)
            
        # Prepare and send the position target message
        target_msg = construct_position_target_message(drone, target_location)
            
        # Send the message to the drone
        drone.send_mavlink(target_msg)
        drone.flush()  # Ensure the message is sent immediately

        print(f"{drone_id}: Sending target position to {target_position}")

        time.sleep(0.1)  # Short delay for high-frequency position updates


def construct_position_target_message(vehicle, location):
    # Extract lat, lon, and alt from LocationGlobalRelative object
    lat = location.lat
    lon = location.lon
    alt = location.alt

    # Construct the MAVLink message for SET_POSITION_TARGET_GLOBAL_INT with adjusted type mask
    msg = vehicle.message_factory.set_position_target_global_int_encode(
        0,                # time_boot_ms (not used)
        0, 0,             # target system and component
        mavutil.mavlink.MAV_FRAME_GLOBAL_RELATIVE_ALT_INT,  # coordinate frame (relative altitude)
        0b0000111111111000,  # type_mask (only position enabled)
        int(lat * 1e7),    # lat_int - Latitude in 1e7 * meters (integer)
        int(lon * 1e7),    # lon_int - Longitude in 1e7 * meters (integer)
        alt,               # altitude in meters (relative to home)
        0, 0, 0,           # X, Y, Z velocities in NED frame (not used)
        0, 0, 0,           # acceleration (not supported yet)
        0, 0)              # yaw and yaw_rate (not supported yet)
    
    return msg
"""


#Converts GPS Coordinates to position coordinates
"""
# Function to convert GPS coordinates (lat, lon, alt) to NED coordinates
def gps_to_ned(drone_lat, drone_lon, drone_alt, target_lat, target_lon, target_alt):
    # Constants for WGS-84 datum (Earth's radius in meters)
    R = 6378137.0  # Earth's radius in meters
    lat_diff = math.radians(target_lat - drone_lat)
    lon_diff = math.radians(target_lon - drone_lon)
    
    # Calculate differences in the NED frame
    north = lat_diff * R
    east = lon_diff * R * math.cos(math.radians(drone_lat))
    down = drone_alt - target_alt
    
    return north, east, down

# Function to move drones to their positions based on calculated GPS coordinates
def move_to_user_position(drones, user_lat, user_lon, user_alt, target_altitude, positions):

    #Moves each drone in `drones` to a position based on the formation pattern relative to the user's position.
    
    #Parameters:
    #- drones: list of drone objects
    #- user_lat, user_lon, user_alt: User's latitude, longitude, and altitude
    #- target_altitude: Target altitude relative to the user's altitude
    #- positions: List of drone target positions (lat, lon) for each drone

    for idx, drone in enumerate(drones):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Get the drone's current GPS position
        current_lat = drone.location.global_frame.lat
        current_lon = drone.location.global_frame.lon
        current_alt = drone.location.global_frame.alt

        # Get the target GPS position for the drone from the positions list
        target_lat, target_lon = positions[idx]

        # Convert target GPS position to NED coordinates relative to the user's position
        north, east, down = gps_to_ned(user_lat, user_lon, user_alt, target_lat, target_lon, user_alt + target_altitude)

        # Create and send the NED position target message
        target_msg = construct_ned_target_message(drone, north, east, down)
        
        # Send the message to the drone
        drone.send_mavlink(target_msg)
        drone.flush()

        print(f"{drone_id}: Moving to target position (N:{north}, E:{east}, D:{down})")

        time.sleep(0.1)  # Short delay to ensure high-frequency updates

# Function to construct MAVLink message for NED coordinates
def construct_ned_target_message(vehicle, north, east, down):
    # Create MAVLink message for local NED positioning
    msg = vehicle.message_factory.set_position_target_local_ned_encode(
        0,                  # time_boot_ms (not used)
        0, 0,               # target system and component
        mavutil.mavlink.MAV_FRAME_LOCAL_NED,  # local NED frame
        0b0000111111111000,  # type_mask (only position enabled)
        north,               # Position in North (meters)
        east,                # Position in East (meters)
        down,                # Position in Down (altitude relative to home)
        0, 0, 0,             # velocities (unused)
        0, 0, 0,             # accelerations (unsupported)
        0, 0)                # yaw and yaw_rate (optional)

    return msg
    """


#Velocity based control, altitude is also velocity based control.

def gps_to_ned_velocity(drone_lat, drone_lon, target_lat, target_lon, user_speed):
    # Constants for Earth's radius in meters (WGS-84)
    R = 6378137.0

    # Calculate differences in latitude and longitude in radians
    lat_diff = math.radians(target_lat - drone_lat)
    lon_diff = math.radians(target_lon - drone_lon)

    # Calculate the NED distances
    north = lat_diff * R
    east = lon_diff * R * math.cos(math.radians(drone_lat))

    # Normalize the direction and scale by the user's speed
    distance = math.sqrt(north**2 + east**2)
    if distance > 0:
        north_velocity = (north / distance) * user_speed
        east_velocity = (east / distance) * user_speed
    else:
        north_velocity = east_velocity = 0

    return north_velocity, east_velocity


def move_to_positions_velocity(drones, triangle_positions, kalman_user_speed, target_altitude, alpha=0.3, altitude_tolerance=0.5):
    for drone, target_position in zip(drones, triangle_positions):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Get the drone's current GPS position and altitude
        current_lat = drone.location.global_relative_frame.lat
        current_lon = drone.location.global_relative_frame.lon
        current_alt = drone.location.global_relative_frame.alt  # Use relative frame for altitude

        # Calculate the NED horizontal velocity to reach the target position
        raw_north_velocity, raw_east_velocity = gps_to_ned_velocity(
            current_lat, current_lon,
            target_position[0], target_position[1],
            kalman_user_speed
        )

        # Apply a low-pass filter to smooth velocities
        filtered_north_velocity = (alpha * raw_north_velocity +
                                   (1 - alpha) * getattr(drone, 'prev_north_velocity', 0))
        filtered_east_velocity = (alpha * raw_east_velocity +
                                  (1 - alpha) * getattr(drone, 'prev_east_velocity', 0))

        # Update previous velocities for filtering in the next iteration
        setattr(drone, 'prev_north_velocity', filtered_north_velocity)
        setattr(drone, 'prev_east_velocity', filtered_east_velocity)

        # Check altitude deviation
        altitude_deviation = abs(current_alt - target_altitude)
        if altitude_deviation > altitude_tolerance:
            print(f"{drone_id}: Altitude deviation detected ({altitude_deviation:.2f} m). Correcting altitude using simple_goto.")
            # Use simple_goto to correct altitude while maintaining position
            drone.simple_goto(LocationGlobalRelative(current_lat, current_lon, target_altitude))
            continue  # Skip velocity command for this iteration

        # Construct and send MAVLink velocity command for NED movement
        send_ned_velocity(drone, filtered_north_velocity, filtered_east_velocity, 0)  # No vertical velocity

        print(f"{drone_id}: Moving towards target with velocities N: {filtered_north_velocity:.2f} m/s, "
              f"E: {filtered_east_velocity:.2f} m/s, maintaining altitude at {target_altitude:.2f} m")

        # Optional: Short delay for smoother control loop
        time.sleep(0.1)



def send_ned_velocity(vehicle, north, east, altitude):
    # Construct MAVLink message with fixed altitude
    msg = vehicle.message_factory.set_position_target_local_ned_encode(
        0,       # time_boot_ms (not used)
        0, 0,    # target system and target component
        mavutil.mavlink.MAV_FRAME_LOCAL_NED,  # Frame of reference
        0b0000111111000111,  # Type mask (only velocities and altitude enabled)
        0, 0, 0,      # x, y positions and altitude (altitude fixed)
        north, east, 0,      # x, y, z velocities (z velocity = 0 for altitude hold)
        0, 0, 0,             # x, y, z acceleration (not supported)
        0, 0)                # yaw, yaw_rate (not supported)
    vehicle.send_mavlink(msg)
    vehicle.flush()



#move with velocitiy and position control
def gps_to_ned_with_velocity(drone_lat, drone_lon, drone_alt, target_lat, target_lon, target_alt, user_speed):
    """
    Calculate NED position and velocity values to reach a target.

    :param drone_lat: Drone's current latitude.
    :param drone_lon: Drone's current longitude.
    :param drone_alt: Drone's current altitude.
    :param target_lat: Target latitude.
    :param target_lon: Target longitude.
    :param target_alt: Target altitude.
    :param user_speed: Speed to approach the target.
    :return: (north, east, down, north_velocity, east_velocity)
    """
    # Constants for Earth's radius in meters (WGS-84)
    R = 6378137.0

    # Calculate differences in latitude and longitude in radians
    lat_diff = math.radians(target_lat - drone_lat)
    lon_diff = math.radians(target_lon - drone_lon)

    # Calculate the NED distances
    north = lat_diff * R
    east = lon_diff * R * math.cos(math.radians(drone_lat))
    down = drone_alt - target_alt  # Altitude difference

    # Normalize the direction and scale by the user's speed for velocity
    distance = math.sqrt(north**2 + east**2)
    if distance > 0:
        north_velocity = (north / distance) * user_speed
        east_velocity = (east / distance) * user_speed
    else:
        north_velocity = east_velocity = 0

    return north, east, down, north_velocity, east_velocity


def move_to_positions_with_ned(drones, triangle_positions, kalman_user_speed, target_altitude, alpha=0.3):
    """
    Move drones using a combination of NED position and velocity control.

    :param drones: List of drone objects.
    :param triangle_positions: List of target positions for the drones.
    :param kalman_user_speed: User's calculated speed.
    :param target_altitude: Target altitude for the drones.
    :param alpha: Smoothing factor for velocity filtering.
    """
    for drone, target_position in zip(drones, triangle_positions):
        drone_id = drone.id if hasattr(drone, 'id') else 'Unknown'

        # Get the drone's current GPS position and altitude
        current_lat = drone.location.global_relative_frame.lat
        current_lon = drone.location.global_relative_frame.lon
        current_alt = drone.location.global_relative_frame.alt

        # Calculate NED position and velocity
        north, east, down, raw_north_velocity, raw_east_velocity = gps_to_ned_with_velocity(
            current_lat, current_lon, current_alt,
            target_position[0], target_position[1], target_altitude,
            kalman_user_speed
        )

        # Apply a low-pass filter to north and east velocities for smoothing
        filtered_north_velocity = (alpha * raw_north_velocity +
                                   (1 - alpha) * getattr(drone, 'prev_north_velocity', 0))
        filtered_east_velocity = (alpha * raw_east_velocity +
                                  (1 - alpha) * getattr(drone, 'prev_east_velocity', 0))

        # Update previous velocities for filtering in the next iteration
        setattr(drone, 'prev_north_velocity', filtered_north_velocity)
        setattr(drone, 'prev_east_velocity', filtered_east_velocity)

        # Construct and send MAVLink position and velocity message
        send_ned_position_velocity(
            drone,
            north, east, down,
            filtered_north_velocity, filtered_east_velocity
        )

        print(f"{drone_id}: Moving to target with position (N:{north:.2f}, E:{east:.2f}, D:{down:.2f}) "
              f"and velocities (N:{filtered_north_velocity:.2f}, E:{filtered_east_velocity:.2f})")

        # Optional: Short delay for smoother control loop
        time.sleep(0.1)


def send_ned_position_velocity(vehicle, north, east, down, north_velocity, east_velocity):
    """
    Send a MAVLink message to control both position and velocity in NED frame.

    :param vehicle: The drone object.
    :param north: Target north position (meters).
    :param east: Target east position (meters).
    :param down: Target down position (meters).
    :param north_velocity: North velocity (m/s).
    :param east_velocity: East velocity (m/s).
    """
    msg = vehicle.message_factory.set_position_target_local_ned_encode(
        0,       # time_boot_ms (not used)
        0, 0,    # target system and target component
        mavutil.mavlink.MAV_FRAME_LOCAL_NED,  # Frame of reference
        0b0000111111000111,  # Type mask (position and velocity enabled)
        north, east, down,   # Target positions in meters
        north_velocity, east_velocity, 0,  # Velocities in m/s (z velocity not used)
        0, 0, 0,             # Accelerations (not used)
        0, 0)                # Yaw and yaw_rate (not used)
    vehicle.send_mavlink(msg)
    vehicle.flush()
