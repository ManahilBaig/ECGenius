# Database Design

## Overview

The schema is **session-based**: each ECG recording is one **session**; raw samples are stored in **readings** (chunks), and **processed_results** and **alerts** are attached to sessions.

---

## Entity-Relationship (Conceptual)

```
  User 1───┐
           │
           ▼
  ECGSession 1───┬─── ECGReading (many chunks)
                 │
                 ├─── ProcessedResult (one or more per session)
                 │
                 └─── Alert (zero or more when abnormality detected)
```

---

## Tables

### 1. `users`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment. |
| email | VARCHAR(255) UNIQUE | Login. |
| hashed_password | VARCHAR(255) | Bcrypt hash. |
| full_name | VARCHAR(255) | Optional. |
| is_active | BOOLEAN | Default true. |
| created_at | DATETIME | Creation time. |

**Role:** Authentication and ownership of sessions. `ecg_sessions.user_id` can be NULL for anonymous/mock use.

---

### 2. `ecg_sessions`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment. |
| user_id | INTEGER FK(users) | Optional. |
| name | VARCHAR(255) | e.g. "Morning reading". |
| sampling_rate_hz | FLOAT | 250–360 for AD8232. |
| source | VARCHAR(50) | `mock`, `esp32_http`, `esp32_websocket`, `esp32_mqtt`. |
| started_at | DATETIME | When recording started. |
| ended_at | DATETIME | When ended (nullable if still recording). |
| total_duration_seconds | FLOAT | Total length of ECG. |
| status | VARCHAR(20) | `recording`, `completed`, `failed`. |

**Role:** One row = one ECG recording session. Supports filtering by user, source, and time.

**Why session-based:**

- ECG is inherently **temporal**: one continuous recording = one session.
- Enables: “all data for this session”, “list my sessions”, “replay”, “compare”.
- Aligns with how ESP32 sends: one logical stream per recording, even if chunked.

---

### 3. `ecg_readings`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment. |
| session_id | INTEGER FK(ecg_sessions) | Session this chunk belongs to. |
| samples | JSON | Array of floats (ADC/voltage). |
| chunk_index | INTEGER | Order of chunk in the session. |
| start_time_offset_ms | FLOAT | Optional: ms from session start. |
| sample_count | INTEGER | `len(samples)`. |

**Role:** Raw ECG in **chunks** to avoid very large rows and to match ESP32’s chunked posts.

**Why chunking:**

- ESP32 sends small buffers (e.g. 180–500 samples per HTTP/WS message).
- Direct mapping: one `POST /upload-chunk` → one `ecg_readings` row.
- For long sessions, we avoid single rows with hundreds of thousands of samples.

---

### 4. `processed_results`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment. |
| session_id | INTEGER FK(ecg_sessions) | Session. |
| bpm | FLOAT | Heart rate. |
| mean_rr_ms | FLOAT | Mean RR interval (ms). |
| rr_std_ms | FLOAT | Std of RR (for irregularity). |
| rr_intervals_ms | JSON | List of RR values (optional). |
| abnormality | VARCHAR(50) | `normal`, `bradycardia`, `tachycardia`, `irregular_rhythm`. |
| num_beats | INTEGER | Number of R-peaks. |
| duration_seconds | FLOAT | Length of segment analyzed. |
| processed_at | DATETIME | When processing ran. |

**Role:** One row per processing run (e.g. when a session is finished or when a segment is analyzed). Frontend and health API use the latest row for a session.

---

### 5. `alerts`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment. |
| session_id | INTEGER FK(ecg_sessions) | Session. |
| alert_type | VARCHAR(50) | `bradycardia`, `tachycardia`, `irregular_rhythm`. |
| severity | VARCHAR(20) | `low`, `medium`, `high`. |
| message | TEXT | Human-readable. |
| bpm_at_alert | FLOAT | BPM when the alert was raised. |
| created_at | DATETIME | When the alert was created. |

**Role:** Record of detected abnormalities for history and dashboards.

---

## Relationships

| From | To | Cardinality |
|------|----|-------------|
| users | ecg_sessions | 1 : N |
| ecg_sessions | ecg_readings | 1 : N |
| ecg_sessions | processed_results | 1 : N |
| ecg_sessions | alerts | 1 : N |

---

## Indexes (and usage)

- `users.email` (unique) — login.
- `ecg_sessions.user_id` — “my sessions”.
- `ecg_sessions.started_at` — ordering and time-range queries.
- `ecg_readings.session_id` — fetch all chunks for a session.
- `processed_results.session_id` — latest result per session.
- `alerts.session_id`, `alerts.created_at` — list alerts by session or globally.

---

## Why Session-Based Storage for ECG

1. **Temporal unit:** One session = one continuous recording; easy to reason about.
2. **Replay and audit:** Reconstruct full waveform and recompute from raw chunks.
3. **Comparison:** Compare sessions (e.g. before/after, different sources).
4. **Hardware transition:** ESP32 can create one session per recording and append chunks; schema stays the same.
