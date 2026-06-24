import sys
import os

# Add backend directory to sys.path so we can import app
sys.path.append(os.path.abspath('ECG FYP/ECG FYP/backend'))

from app.main import app

print("Registered Routes:")
for route in app.routes:
    print(f"{route.path} {route.name} {route.methods}")
