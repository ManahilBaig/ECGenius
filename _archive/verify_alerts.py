import httpx

BASE_URL = "http://127.0.0.1:8001/api/v1/ecg"

def check_alerts():
    print("Checking Alerts...")
    try:
        r = httpx.get(f"{BASE_URL}/alerts")
        alerts = r.json()
        print(f"Found {len(alerts)} alerts.")
        for a in alerts[:5]:
            print(f" - [{a['severity'].upper()}] {a['alert_type']}: {a['message']}")
            
        print("\nChecking Sessions...")
        r = httpx.get(f"{BASE_URL}/sessions")
        sessions = r.json()
        for s in sessions[:5]:
             # Get health to see status
             h_r = httpx.get(f"{BASE_URL}/sessions/{s['id']}/health")
             if h_r.status_code == 200:
                 h = h_r.json()
                 print(f" - Session {s['id']} ({s['name']}): {h['status']} (BPM: {h['bpm']})")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_alerts()
