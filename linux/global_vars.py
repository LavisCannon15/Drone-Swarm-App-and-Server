import threading

# Create a global event to control the stopping of operations
stop_operations_event = threading.Event()
