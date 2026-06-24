import sys
import os
sys.path.append(os.path.abspath('ECG FYP/ECG FYP/backend'))

from fastapi.testclient import TestClient
from app.main import app

def run():
    with TestClient(app) as client:
        print('Testing GET /api/v1/ecg/mock/sample...')
        r = client.get("/api/v1/ecg/mock/sample")
        print(f'Status: {r.status_code}')
        if r.status_code == 200:
            data = r.json()
            samples = data.get('samples', [])
            print(f'Got {len(samples)} samples. Rate: {data.get("sampling_rate_hz")}')
        else:
            print(f'Error: {r.text}')

if __name__ == "__main__":
    run()
