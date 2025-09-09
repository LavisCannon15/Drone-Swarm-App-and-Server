# File: test/dronekit_takeoff_force_disarm.py
from dronekit import connect, VehicleMode
from pymavlink import mavutil
import time

CONNECTION_STRING = "127.0.0.1:14550"
TARGET_ALT_M = 2.0

def force_disarm_in_air(vehicle):
    """
    Force disarm even if airborne.
    This immediately cuts motor outputs; the aircraft will fall.
    """
    print(">>> FORCING DISARM (motors will stop NOW)")
    msg = vehicle.message_factory.command_long_encode(
        0, 0,  # target_system, target_component (0 = autopilot)
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,  # 400
        0,      # confirmation
        0,      # param1: 0 = disarm
        21196,  # param2: magic value to allow in-air disarm
        0, 0, 0, 0, 0
    )
    vehicle.send_mavlink(msg)
    vehicle.flush()

def arm_and_takeoff_then_force_disarm(target_altitude: float) -> None:
    """Arm the vehicle, fly to target_altitude meters, then force-disarm mid-air."""
    print("Connecting to vehicle...")
    vehicle = connect(CONNECTION_STRING, wait_ready=True)

    try:
        # Pre-arm checks
        print("Performing pre-arm checks...")
        while not vehicle.is_armable:
            time.sleep(0.5)

        # Arm
        print("Setting GUIDED and arming motors...")
        vehicle.mode = VehicleMode("GUIDED")
        while vehicle.mode.name != "GUIDED":
            time.sleep(0.2)

        vehicle.armed = True
        while not vehicle.armed:
            time.sleep(0.2)

        # Take off
        print(f"Taking off to {target_altitude:.1f} m")
        vehicle.simple_takeoff(target_altitude)

        # Climb until near target altitude
        while True:
            alt = vehicle.location.global_relative_frame.alt or 0.0
            print(f"Altitude: {alt:.2f} m")
            if alt >= target_altitude * 0.95:
                print("Reached target altitude.")
                break
            time.sleep(0.5)

        # Brief pause (optional)
        time.sleep(1.0)

        # >>> FORCE DISARM MID-AIR <<<
        force_disarm_in_air(vehicle)

        # Wait until the vehicle reports disarmed (on ground or mid-air after cut)
        start = time.time()
        while vehicle.armed and (time.time() - start) < 10:
            time.sleep(0.2)

        if vehicle.armed:
            print("Warning: Vehicle still reports ARMED after force-disarm command.")
        else:
            print("Vehicle is DISARMED.")

    finally:
        vehicle.close()
        print("Connection closed.")

if __name__ == "__main__":
    arm_and_takeoff_then_force_disarm(TARGET_ALT_M)
