# REST API Specification

Base URL: `/api/v1`. All request/response bodies are JSON unless noted.

---

## Authentication (Basic)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth/register` | POST | Create user. |
| `/auth/login` | POST | Login (OAuth2 form: `username`=email, `password`); returns JWT. |

**Protected routes (optional):** Send `Authorization: Bearer <token>`. For FYP, many ECG routes work without auth.

---

## Auth Endpoints

### POST `/auth/register`

**Request:**

```json
{
  "email": "user@example.com",
  "password": "secret",
  "full_name": "Optional Name"
}
```

**Response:** `UserOut` (id, email, full_name, is_active).

---

### POST `/auth/login`

**Request:** `application/x-www-form-urlencoded`

- `username` = email  
- `password` = password  

**Response:**

```json
{
  "access_token": "eyJ...",
  "token_type": "bearer"
}
```

---

## ECG Endpoints

### POST `/ecg/sessions`

Create a new session (for chunked upload).

**Request:**

```json
{
  "name": "Morning reading",
  "sampling_rate_hz": 360,
  "source": "mock"
}
```

`source`: `mock` | `esp32_http` | `esp32_websocket` | `esp32_mqtt`.

**Response:** `ECGSessionOut` (id, user_id, name, sampling_rate_hz, source, started_at, ended_at, total_duration_seconds, status).

---

### GET `/ecg/sessions`

List sessions.

**Query:** `skip`, `limit` (default 50, max 200).

**Response:** `[ECGSessionOut]`.

---

### GET `/ecg/sessions/{session_id}`

Get one session.

**Response:** `ECGSessionOut`.

---

### POST `/ecg/upload-chunk`

Append a chunk of ECG (ESP32 or mock stream).

**Request:**

```json
{
  "session_id": 1,
  "samples": [0.1, -0.05, 0.2, ...],
  "chunk_index": 0,
  "start_time_offset_ms": 0
}
```

- `samples`: 1–10000 floats.  
- `chunk_index`: order in the session.

**Response:**

```json
{
  "session_id": 1,
  "chunk_index": 0,
  "samples_received": 180
}
```

---

### POST `/ecg/upload-bulk`

Create a session, store samples, run processing, and create alerts. For mock/batch or when ESP32 sends a full buffer.

**Request:**

```json
{
  "samples": [0.1, -0.05, ...],
  "sampling_rate_hz": 360,
  "session_name": "Test",
  "user_id": null
}
```

- `samples`: 1–500000.  
- `session_name`, `user_id`: optional.

**Response:**

```json
{
  "session_id": 1,
  "bpm": 72.5,
  "abnormality": "normal",
  "num_beats": 12,
  "duration_seconds": 10.0
}
```

---

### GET `/ecg/sessions/{session_id}/waveform`

ECG waveform for plotting.

**Query:** `filtered` (default true) — if true, returns bandpass-filtered (0.5–40 Hz) signal.

**Response:**

```json
{
  "session_id": 1,
  "sampling_rate_hz": 360,
  "points": [{"t_ms": 0.0, "value": 0.1}, ...],
  "is_filtered": true
}
```

---

### GET `/ecg/sessions/{session_id}/health`

BPM and health status. Uses latest `ProcessedResult` or runs processing if none.

**Response:**

```json
{
  "bpm": 72.5,
  "status": "normal",
  "num_beats": 12,
  "duration_seconds": 10.0,
  "mean_rr_ms": 827.6
}
```

`status`: `normal` | `bradycardia` | `tachycardia` | `irregular_rhythm`.

---

### GET `/ecg/sessions/{session_id}/results`

All processed results for a session.

**Response:** `[ProcessedResultOut]` (id, session_id, bpm, mean_rr_ms, rr_std_ms, abnormality, num_beats, duration_seconds, processed_at).

---

### GET `/ecg/alerts`

List alerts.

**Query:**

- `session_id` (optional): filter by session.  
- `skip`, `limit` (default 50, max 200).

**Response:** `[AlertOut]` (id, session_id, alert_type, severity, message, bpm_at_alert, created_at).

---

### GET `/ecg/mock/sample`

Mock ECG for testing (from MIT-BIH–style CSV or synthetic).

**Response:**

```json
{
  "samples": [0.1, -0.05, ...],
  "sampling_rate_hz": 360
}
```

Use with `POST /ecg/upload-bulk` or to build chunked `POST /ecg/upload-chunk` requests.

---

## Error Responses

- **400:** Validation error or `ValueError` from processing (e.g. too-short or corrupted ECG). Body: `{"detail": "..."}`.
- **401:** Invalid or missing auth (on protected routes).
- **404:** Session or resource not found. Body: `{"detail": "Session not found"}`.

---

## OpenAPI (Swagger)

Interactive docs: **`/docs`** (Swagger UI).  
Schema: **`/openapi.json`**.
