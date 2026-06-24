import sys
import os

# Add backend directory to sys.path
sys.path.append(os.path.abspath('ECG FYP/ECG FYP/backend'))

from fastapi.testclient import TestClient
from app.main import app

def run_tests():
    with TestClient(app) as client:
        print('Testing internal API routes (with startup events)...')

        # 1. Test Root
        r = client.get("/")
        print(f'Root: {r.status_code} {r.json()}')

        # 2. Test Get Sessions
        r = client.get("/api/v1/ecg/sessions")
        print(f'Get Sessions: {r.status_code}')

        # 3. Test Create Session
        payload = {
            "name": "Internal Test Session",
            "sampling_rate_hz": 360,
            "source": "mock"
        }
        r = client.post("/api/v1/ecg/sessions", json=payload)
        print(f'Create Session: {r.status_code}')

        if r.status_code == 200:
            print(f'Session: {r.json()}')
            sid = r.json()['id']
            
            # 4. Test Mock Sample
            r = client.post(f"/api/v1/ecg/sessions/{sid}/mock-sample")
            print(f'Mock Sample: {r.status_code}')
            if r.status_code == 200:
                 print(f'Message: {r.json().get("message")}')
        elif r.status_code == 404:
            print(f'Error Body: {r.text}')

    print('Done.')

if __name__ == "__main__":
    try:
        run_tests()
    except Exception as e:
        print(f"Error running tests: {e}")
        import traceback
        traceback.print_exc()
