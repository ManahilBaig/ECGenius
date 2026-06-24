# System Architecture: ECG Monitoring (ESP32 + AD8232)

## Overview

The system is a **hardware-ready backend** for real-time ECG monitoring. The Flutter app records 15-second ECG sessions, finalizes them with optional symptoms, and the backend stores raw samples plus processed results.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ECG MONITORING SYSTEM                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────┐ │
│  │  APP /       │     │   BACKEND    │     │       FRONTEND                │ │
│  │  ESP32       │────▶│   (FastAPI)  │────▶│   (ECG / History Mobile)      │ │
│  │  Data Source │     │              │     │   - Waveform plot             │ │
│  └──────────────┘     │  • Ingest    │     │   - BPM / health status       │ │
│                      │  • Process   │     │   - Alerts / history           │ │
│                      │  • Store     │     └──────────────────────────────┘ │
│                      │  • Expose API│                                       │
│                            └──────┬───────┘                                       │
│                                   │                                                │
│                            ▼                                                │
│                     ┌──────────────┐                                        │
│                     │   SQLite /   │                                        │
│                     │   Database   │                                        │
│                     └──────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Pipeline

### 1. **App recording flow**

| Step | Description |
|------|-------------|
| 1 | Flutter creates an ECG session and records 15 seconds of samples. |
| 2 | The app navigates to symptom entry when the fixed recording ends. |
| 3 | `POST /api/v1/ecg/sessions/{id}/complete` stores samples, BPM, duration, and optional symptoms. |
| 4 | **Processing**: bandpass 0.5–40 Hz, R-peak detection, BPM, RR intervals, abnormality. |
| 5 | **Storage**: `ecg_sessions`, `ecg_readings`, `processed_results`, `alerts`. |
| 6 | **API**: waveform, health, results, alerts for frontend. |

### 2. **Hardware phase (later)**

Integrate **ESP32** source:

- **AD8232** → analog ECG → **ESP32 ADC** → digital stream.
- ESP32 sends over **Wi‑Fi** via **HTTP**, **WebSocket**, or **MQTT**.
- Payload format stays the same: `{ "session_id", "samples", "chunk_index" }` or equivalent.
- **No backend rewrite**: same `/upload-chunk` and processing.

---

## Component Roles

| Component | Role |
|-----------|------|
| **ECG processor** | Baseline removal, bandpass, R-peaks, BPM, RR, abnormality. |
| **Routers** | REST: sessions, complete, upload-chunk, upload-bulk, waveform, health, results, alerts. |
| **Database** | Session-based storage: users, sessions, readings (chunks), results, alerts. |
| **Alert service** | Creates `alerts` when bradycardia, tachycardia, or irregular rhythm is detected. |

---

## Why Session-Based Storage?

- **ECG is temporal**: one logical “recording” = one **session** (e.g. 30 s, 5 min).
- **Queries**: “Get all data for this session”, “List my sessions”, “Replay session”.
- **Chunking**: `ecg_readings` stores **chunks** (e.g. 1–5 s) to avoid huge rows and to match ESP32’s chunked sends.
- **Audit and comparison**: Sessions support history, comparison, and reuse for validation (e.g. MIT-BIH vs real hardware).

---

## Scalability (Brief)

- **Single instance**: SQLite is enough for demos and FYP.
- **Larger scale**: switch `DATABASE_URL` to PostgreSQL; consider binary/blob for long `ecg_readings`; add Redis for live streaming if needed.
- **ESP32 volume**: many devices can POST to `/upload-chunk`; optional rate limiting and auth per device.

---

## Security and Reliability

- **Input validation**: Pydantic limits on `samples` length; `process_ecg` rejects too-short, NaN, Inf, and out-of-range data.
- **Corrupted ECG**: `ValueError` from `process_ecg` → 400 with a clear message.
- **Auth**: JWT (register/login); optional `Authorization: Bearer` on sensitive routes.
- **Config**: thresholds (brady/tachy), bandpass, DB, and `SECRET_KEY` via env (see `.env.example`).

---

## Document Map

- **Signal processing**: `docs/SIGNAL_PROCESSING.md`
- **Database**: `docs/DATABASE_DESIGN.md`
- **APIs**: `docs/API_SPECIFICATION.md`
- **Hardware transition**: `docs/HARDWARE_TRANSITION.md`
