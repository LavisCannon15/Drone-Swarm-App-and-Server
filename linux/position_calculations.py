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



def calculate_rotation_params(offset_distance, angle_increment):
    """
    Calculate the rotation time and speed based on the offset distance and angle increment.

    :param offset_distance: The distance from the center of rotation.
    :param angle_increment: The angle increment for each step of rotation in degrees.
    :return: A tuple containing (speed, rotation_time)
    """
    # Calculate the circumference of the circular path
    circumference = 2 * math.pi * offset_distance
    
    # Calculate the number of increments needed to complete a full rotation (360 degrees)
    increments = 360 / angle_increment

    # Calculate the total time to complete a full rotation
    rotation_time = circumference / increments  # Time for one full rotation

    # Calculate speed based on circumference and rotation time
    speed = circumference / rotation_time
    
    return speed, rotation_time

def calculate_rotation_params2(offset_distance, set_speed):
    circumference = 2 * math.pi * offset_distance
    cycle_time = circumference / set_speed
    return set_speed, cycle_time



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
