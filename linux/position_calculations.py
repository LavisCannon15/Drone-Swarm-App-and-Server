import math
from geopy.distance import great_circle

# Triangle Formation Calculations
def calculate_triangle_positions(reference_lat, reference_lon, offset_distance):
    offset_distance_meters = offset_distance / 111320
    triangle_positions = [
        (reference_lat + offset_distance_meters, reference_lon),
        (reference_lat - offset_distance_meters / 2, reference_lon + (offset_distance_meters * (3**0.5)) / 2),
        (reference_lat - offset_distance_meters / 2, reference_lon - (offset_distance_meters * (3**0.5)) / 2)
    ]
    return triangle_positions


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
    angle_radians = math.radians(angle_degrees)
    center_lat = sum(lat for lat, lon in positions) / len(positions)
    center_lon = sum(lon for lat, lon in positions) / len(positions)
    
    rotated_positions = []
    for lat, lon in positions:
        relative_lat = lat - center_lat
        relative_lon = lon - center_lon
        rotated_lat = relative_lat * math.cos(angle_radians) - relative_lon * math.sin(angle_radians)
        rotated_lon = relative_lat * math.sin(angle_radians) + relative_lon * math.cos(angle_radians)
        new_lat = rotated_lat + center_lat
        new_lon = rotated_lon + center_lon
        rotated_positions.append((new_lat, new_lon))
    
    return rotated_positions


# Calculating Drones' Revolving Positions
def calculate_revolving_positions(current_lat, current_lon, offset_distance, num_drones, angle_offset):
    positions = []
    for i in range(num_drones):
        angle_rad = math.radians(angle_offset + i * (360 / num_drones))
        new_lat = current_lat + (offset_distance / 111320) * math.cos(angle_rad)
        new_lon = current_lon + (offset_distance / (111320 * math.cos(math.radians(current_lat)))) * math.sin(angle_rad)
        positions.append((new_lat, new_lon))
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
            if distance < min_distance:
                adjustment = (min_distance - distance) / 2
                triangle_positions[i] = (
                    drone1_pos[0] + adjustment * (drone2_pos[0] - drone1_pos[0]) / distance,
                    drone1_pos[1] + adjustment * (drone2_pos[1] - drone1_pos[1]) / distance
                )
                triangle_positions[j] = (
                    drone2_pos[0] - adjustment * (drone2_pos[0] - drone1_pos[0]) / distance,
                    drone2_pos[1] - adjustment * (drone2_pos[1] - drone1_pos[1]) / distance
                )
    return triangle_positions


# Ensuring Equal Distance from the User
def ensure_equal_distance_from_user(drones, triangle_positions, current_lat, current_lon, min_distance):
    for i, drone_pos in enumerate(triangle_positions):
        distance_to_user = great_circle(drone_pos, (current_lat, current_lon)).meters
        if distance_to_user < min_distance:
            adjustment = min_distance - distance_to_user
            direction = [drone_pos[0] - current_lat, drone_pos[1] - current_lon]
            direction_normalized = [coord / math.sqrt(direction[0]**2 + direction[1]**2) for coord in direction]
            triangle_positions[i] = (
                drone_pos[0] + adjustment * direction_normalized[0],
                drone_pos[1] + adjustment * direction_normalized[1]
            )
    return triangle_positions
