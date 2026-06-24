import asyncio
import httpx
import math
import random
import time

BASE_URL = "http://127.0.0.1:8001/api/v1/ecg"

def generate_ecg_chunk(sampling_rate: int, duration_seconds: float, bpm: float) -> list[float]:
    """
    Generate synthetic ECG data at a specific BPM.
    Simplified version of the backend logic.
    """
    n = int(sampling_rate * duration_seconds)
    t_step = 1.0 / sampling_rate
    f_hr = bpm / 60.0  # heart rate in Hz
    
    samples = []
    
    # We'll generate a continuous signal
    for i in range(n):
        t = i * t_step
        
        # Base rhythm: P, QRS, T waves approximation
        # Pulse repeats every 1/f_hr seconds
        cycle_pos = (t * f_hr) % 1.0
        
        val = 0.0
        
        # P wave (around 0.2 of cycle)
        if 0.15 < cycle_pos < 0.25:
            val += 0.15 * math.exp(-((cycle_pos - 0.2) ** 2) / 0.002)
            
        # QRS complex (around 0.45 of cycle)
        if 0.4 < cycle_pos < 0.5:
             # Q
             val -= 0.15 * math.exp(-((cycle_pos - 0.44) ** 2) / 0.0005)
             # R (Sharp peak)
             val += 1.0 * math.exp(-((cycle_pos - 0.45) ** 2) / 0.0005)
             # S
             val -= 0.25 * math.exp(-((cycle_pos - 0.46) ** 2) / 0.0005)
             
        # T wave (around 0.7 of cycle)
        if 0.6 < cycle_pos < 0.8:
            val += 0.25 * math.exp(-((cycle_pos - 0.7) ** 2) / 0.004)
            
        # Add some noise
        val += random.gauss(0, 0.05)
        
        samples.append(val)
        
    return samples

async def create_and_upload_session(name: str, bpm: float):
    print(f"\n--- Creating Session: {name} ({bpm} BPM) ---")
    async with httpx.AsyncClient() as client:
        # 1. Generate Data (10 seconds)
        print(f"Generating 10s of synthetic ECG data at {bpm} BPM...")
        sampling_rate = 360
        samples = generate_ecg_chunk(sampling_rate, 10.0, bpm)
        
        # 2. Upload Bulk (Creates session + uploads data + processes it)
        payload = {
            "user_id": 1,
            "session_name": f"{name} - {int(time.time())}",
            "sampling_rate_hz": sampling_rate,
            "samples": samples
        }
        
        try:
            r = await client.post(f"{BASE_URL}/upload-bulk", json=payload, timeout=30.0)
            if r.status_code == 200:
                data = r.json()
                print(f"✅ Success! Session ID: {data['session_id']}")
                print(f"   Detected BPM: {data['bpm']:.1f}")
                print(f"   Abnormality: {data['abnormality']}")
                return data['session_id']
            elif r.status_code == 307:
                 # Follow redirect if needed (though httpx usually handles this if configured)
                loc = r.headers.get('location')
                print(f"   Redirected to {loc}, retrying...")
                r = await client.post(loc, json=payload, timeout=30.0)
                if r.status_code == 200:
                    data = r.json()
                    print(f"✅ Success! Session ID: {data['session_id']}")
                    return data['session_id']
            
            print(f"❌ Failed: {r.status_code} - {r.text[:200]}")
        except Exception as e:
            print(f"❌ Error: {e}")

async def main():
    print("Starting Dummy Data Generation...")
    
    # 1. Normal Rhythm (Skip to avoid duplicates)
    # await create_and_upload_session("Normal Rhythm", 75.0)
    
    # 2. Tachycardia (High Heart Rate) - Boosted to 220 (expecting halving to ~110)
    await create_and_upload_session("Tachycardia Event (High)", 220.0)
    
    # 3. Bradycardia (Low Heart Rate)
    await create_and_upload_session("Bradycardia Event", 50.0)
    
    print("\nDone! Refresh the app to see the new sessions.")

if __name__ == "__main__":
    asyncio.run(main())
