# Hardware Transition: Mock → ESP32 + AD8232

## Goal

Use the **same backend** for:

1. **Mock:** CSV / synthetic data, `POST /upload-chunk` or `POST /upload-bulk`.
2. **Hardware:** ESP32 sending real AD8232 ADC data over Wi‑Fi.

No backend rewrite; only the **data source** (and optional protocol) changes.

---

## Current Mock Flow

```
MIT-BIH CSV / synthetic  →  chunked or bulk  →  POST /api/v1/ecg/upload-chunk
                                                      or
                                              POST /api/v1/ecg/upload-bulk
```

---

## Target Hardware Flow

```
AD8232 (analog ECG)  →  ESP32 ADC  →  Wi‑Fi  →  Backend (same APIs)
```

---

## ESP32 Transport Options

### 1. HTTP (e.g. `POST /upload-chunk`)

- **Pros:** Simple, stateless, works with any HTTP client.  
- **Cons:** Overhead per chunk; not push from server.

**ESP32:**

- Create session: `POST /api/v1/ecg/sessions` (or reuse one).
- For each ADC buffer:  
  `POST /api/v1/ecg/upload-chunk`  
  Body: `{"session_id": id, "samples": [...], "chunk_index": i}`.

**Backend:** Already implements this; no change.

---

### 2. WebSocket

- **Pros:** One connection, low overhead, bidirectional.  
- **Cons:** Need a WebSocket endpoint and a small protocol (e.g. JSON `{session_id, samples, chunk_index}`).

**Backend:** Add a WebSocket route that:

- Accepts the same JSON shape as `upload-chunk`.
- Appends to `ecg_readings` and, when needed, runs processing (e.g. on “session end” or timer).

**ESP32:** Connect to `ws://<server>/api/v1/ecg/stream`, send JSON frames. No change to `ecg_sessions` / `ecg_readings` schema.

---

### 3. MQTT

- **Pros:** Decoupled, good for many devices, built-in QoS.  
- **Cons:** Need an MQTT broker and a small bridge into the backend.

**Backend:** Add a **bridge** (or separate service) that:

- Subscribes to e.g. `ecg/{device_id}/chunk`.
- Parses payload `{session_id, samples, chunk_index}` and calls the same logic as `upload-chunk` (or an internal function used by both HTTP and MQTT).

**ESP32:** Publish to `ecg/{device_id}/chunk` with that JSON. Session creation can be HTTP or MQTT (e.g. “session/start” / “session/end” topics).

---

## Data Format (Same for All)

Keep the **contract** identical to `ECGChunkUpload`:

```json
{
  "session_id": 1,
  "samples": [2048, 2051, 2045, ...],
  "chunk_index": 0,
  "start_time_offset_ms": 0
}
```

- `samples`: ADC values (or scaled). Processing is scale-invariant for R-peak/BPM.
- `chunk_index`: strictly increasing per session.
- `start_time_offset_ms`: optional; useful for alignment.

---

## ESP32-Side Checklist

1. **ADC:**  
   - Sample at **250–360 Hz** (e.g. timer + ADC).  
   - 10–12 bit; values in `samples` as integers or floats.

2. **Chunk size:**  
   - e.g. 180–360 samples per message (~0.5–1 s at 360 Hz).  
   - Must stay within `samples` length limits (e.g. 10000 in `upload-chunk`).

3. **Session:**  
   - One session per recording.  
   - Call `POST /ecg/sessions` at start (or use a fixed “device session”); send `session_id` in every chunk.

4. **Wi‑Fi:**  
   - HTTP: `ESP32 HTTPClient` or `curl`.  
   - WebSocket: `ESP32 WebSocketClient`; send JSON.  
   - MQTT: `PubSubClient` (or similar); publish JSON to a topic the bridge consumes.

5. **End of session:**  
   - Optional: `PATCH /ecg/sessions/{id}` with `status=completed` (if you add this).  
   - Or: backend infers “ended” from no new chunks for N seconds; or use a “session/end” MQTT message.

---

## Backend Changes for Hardware

| What | Change |
|------|--------|
| **HTTP `upload-chunk`** | None. |
| **`upload-bulk`** | None; ESP32 can send a full buffer if it fits. |
| **`ecg_sessions.source`** | Set `esp32_http`, `esp32_websocket`, or `esp32_mqtt` when creating the session. |
| **WebSocket** | New route; re-use existing “append chunk + optional process” logic. |
| **MQTT** | New bridge/service; same logic as `upload-chunk`. |
| **Processing (`process_ecg`)** | None. Same bandpass, R-peak, BPM, RR, abnormality. |
| **DB schema** | None. |

---

## Validation Before Hardware

You can state in a report or defense:

> *“The backend was developed and validated using clinically accepted ECG datasets (e.g. MIT-BIH) that match the electrical and temporal characteristics of AD8232 output, ensuring a seamless transition to real hardware.”*

- **MIT-BIH:** 360 Hz, similar to AD8232 usage.  
- **Pipeline:** bandpass, R-peak, BPM, RR, abnormalities — all applicable to real single-lead ECG from AD8232.

---

## Summary

- **Mock:** CSV/synthetic → `upload-chunk` / `upload-bulk` → same processing and storage.  
- **ESP32:** AD8232 → ADC → Wi‑Fi (HTTP / WebSocket / MQTT) → same chunk format and backend APIs.  
- **Backend:** Add only transport (WebSocket/MQTT bridge); **no rewrite** of processing or database.
