import asyncio
import os
import sys
import types

# Stub external dependencies before importing the module under test
sys.modules['dronekit'] = types.SimpleNamespace(connect=lambda *args, **kwargs: None)

operate_calls = []


def fake_operate_drones(drone_list, takeoff_altitude, target_altitude, command_data):
    operate_calls.append(list(drone_list))


def fake_land(vehicle, drone_id):
    pass

sys.modules['drone_operations'] = types.SimpleNamespace(
    operate_drones=fake_operate_drones,
    land=fake_land,
)
sys.modules['error_handler'] = types.SimpleNamespace()

sys.path.append(os.path.dirname(__file__))
import websocket_server as ws


async def fake_log_message(message):
    pass


ws.log_message = fake_log_message


class DummyVehicle:
    def close(self):
        self.closed = True


async def run_sequence():
    vehicle = DummyVehicle()
    ws.vehicles = {'drone1': vehicle}
    await ws.handle_start_operations({})
    await ws.handle_stop_operations()
    assert ws.vehicles['drone1'] is vehicle
    await ws.handle_start_operations({})
    assert ws.vehicles['drone1'] is vehicle
    await ws.handle_stop_operations()


def test_start_stop_start_reuses_vehicle():
    asyncio.run(run_sequence())
    assert len(operate_calls) == 2
    assert operate_calls[0][0] is operate_calls[1][0]
