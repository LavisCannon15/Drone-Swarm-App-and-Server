# File: test/dronekit_takeoff_land.py
from dronekit import connect, VehicleMode, LocationGlobalRelative
import time

CONNECTION_STRING = "REPLACE_WITH_YOUR_CONNECTION_STRING"

def arm_and_takeoff(target_altitude: float) -> None:
    """Arm the vehicle and fly to target_altitude meters."""
    print("Connecting to vehicle...")
    vehicle = connect(CONNECTION_STRING, wait_ready=True)

    try:
        # Pre-arm checks
        print("Performing pre-arm checks...")
        while not vehicle.is_armable:
            time.sleep(1)

        # Arm
        print("Arming motors...")
        vehicle.mode = VehicleMode("GUIDED")
        vehicle.armed = True
        while not vehicle.armed:
            time.sleep(1)

        # Take off
        print(f"Taking off to {target_altitude} m")
        vehicle.simple_takeoff(target_altitude)

        while True:
            alt = vehicle.location.global_relative_frame.alt
            print(f"Altitude: {alt:.1f} m")
            if alt >= target_altitude * 0.95:
                print("Reached target altitude.")
                break
            time.sleep(1)

        # Hover briefly
        time.sleep(5)

        # Land
        print("Landing...")
        vehicle.mode = VehicleMode("LAND")
        while vehicle.armed:
            time.sleep(1)
        print("Landed.")

    finally:
        vehicle.close()
        print("Connection closed.")

if __name__ == "__main__":
    arm_and_takeoff(5)   # Example: take off to 5 meters
