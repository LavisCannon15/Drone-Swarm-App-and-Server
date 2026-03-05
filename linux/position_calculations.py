import math
from geopy.distance import great_circle


EARTH_RADIUS_M = 6378137.0


def _destination_point(reference_lat, reference_lon, distance_m, bearing_deg):
    """Project a lat/lon point by distance (m) and bearing (deg)."""
    if distance_m <= 0:
        return (reference_lat, reference_lon)

    lat1 = math.radians(reference_lat)
    lon1 = math.radians(reference_lon)
    bearing = math.radians(bearing_deg)
    angular_distance = distance_m / EARTH_RADIUS_M

    lat2 = math.asin(
        math.sin(lat1) * math.cos(angular_distance)
        + math.cos(lat1) * math.sin(angular_distance) * math.cos(bearing)
    )
    lon2 = lon1 + math.atan2(
        math.sin(bearing) * math.sin(angular_distance) * math.cos(lat1),
        math.cos(angular_distance) - math.sin(lat1) * math.sin(lat2),
    )

    lon2 = (lon2 + math.pi) % (2 * math.pi) - math.pi
    return (math.degrees(lat2), math.degrees(lon2))


def _initial_bearing_deg(lat1, lon1, lat2, lon2):
    """Initial bearing from point1 to point2 in degrees [0, 360)."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dlambda = math.radians(lon2 - lon1)

    y = math.sin(dlambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
    bearing = math.degrees(math.atan2(y, x))
    return (bearing + 360.0) % 360.0


# Triangle Formation Calculations
def calculate_triangle_positions(reference_lat, reference_lon, offset_distance, angle_offset=0.0):
    return calculate_revolving_positions(
        reference_lat,
        reference_lon,
        offset_distance,
        3,
        angle_offset,
    )


# Swapping Drones' Positions
def swap_triangle_positions(positions, counter):
    if counter == 0:
        return positions
    elif counter == 1:
        return [positions[2], positions[0], positions[1]]
    elif counter == 2:
        return [positions[1], positions[2], positions[0]]
    return positions


# Rotating the Triangle Formation
def rotate_triangle_around_center(positions, angle_degrees):
    if not positions:
        return positions

    center_lat = sum(lat for lat, lon in positions) / len(positions)
    center_lon = sum(lon for lat, lon in positions) / len(positions)

    rotated_positions = []
    for lat, lon in positions:
        radius = great_circle((center_lat, center_lon), (lat, lon)).meters
        bearing = _initial_bearing_deg(center_lat, center_lon, lat, lon)
        rotated_positions.append(
            _destination_point(center_lat, center_lon, radius, bearing + angle_degrees)
        )

    return rotated_positions


# Calculating Drones' Revolving Positions
def calculate_revolving_positions(current_lat, current_lon, offset_distance, num_drones, angle_offset):
    if num_drones <= 0:
        return []

    radius = max(0.0, float(offset_distance))
    positions = []
    for i in range(num_drones):
        bearing = angle_offset + i * (360.0 / num_drones)
        positions.append(_destination_point(current_lat, current_lon, radius, bearing))
    return positions



def calculate_rotation_params(offset_distance, linear_speed):
    """Calculate angular velocity and cycle time for a circular path.

    Parameters:
        offset_distance (float): Radius of the circular path in **meters**.
        linear_speed (float): Desired linear (tangential) speed in **meters/second**.

    Returns:
        tuple: ``(linear_speed, cycle_time)`` where ``cycle_time`` is the time in
        **seconds** required to complete one full revolution at ``linear_speed``.
    """

    if offset_distance <= 0 or linear_speed <= 0:
        return max(linear_speed, 0.0), float("inf")

    # Angular velocity (rad/s) using omega = v / r
    angular_velocity = linear_speed / offset_distance

    # Time for one full rotation based on angular velocity
    cycle_time = (2 * math.pi) / angular_velocity

    return linear_speed, cycle_time



# Ensuring Equal Distance Between Drones
def ensure_equal_distance(drones, triangle_positions, min_distance):
    for i in range(len(drones)):
        for j in range(i + 1, len(drones)):
            drone1_pos = triangle_positions[i]
            drone2_pos = triangle_positions[j]
            distance = great_circle(drone1_pos, drone2_pos).meters
            if distance < min_distance and distance > 0:
                adjustment = (min_distance - distance) / 2
                bearing_12 = _initial_bearing_deg(
                    drone1_pos[0], drone1_pos[1], drone2_pos[0], drone2_pos[1]
                )
                triangle_positions[i] = _destination_point(
                    drone1_pos[0], drone1_pos[1], adjustment, bearing_12 + 180.0
                )
                triangle_positions[j] = _destination_point(
                    drone2_pos[0], drone2_pos[1], adjustment, bearing_12
                )
    return triangle_positions


# Ensuring Equal Distance from the User
def ensure_equal_distance_from_user(drones, triangle_positions, current_lat, current_lon, min_distance):
    for i, drone_pos in enumerate(triangle_positions):
        distance_to_user = great_circle(drone_pos, (current_lat, current_lon)).meters
        if distance_to_user < min_distance:
            bearing = _initial_bearing_deg(current_lat, current_lon, drone_pos[0], drone_pos[1])
            triangle_positions[i] = _destination_point(
                current_lat, current_lon, min_distance, bearing
            )
    return triangle_positions
