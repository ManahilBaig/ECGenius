# System Architecture: ECG Monitoring (ESP32 + AD8232)

## Overview

The system is a **hardware-ready backend** for real-time ECG monitoring. It is developed and validated using **mock data** that mimics ESP32 + AD8232 output, so that algorithms and APIs work before physical hardware is available.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ECG MONITORING SYSTEM                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────┐ │
│  │  MOCK /      │     │   BACKEND    │     │       FRONTEND                │ │
│  │  ESP32       │────▶│   (FastAPI)  │────▶│   (Dashboard / Mobile)       │ │
│  │  Data Source │     │              │     │   - Waveform plot             │ │
│  └──────────────┘     │  • Ingest    │     │   - BPM / health status       │ │
│                      │  • Process   │     │   - Alerts / history           │ │
│  MIT-BIH /           │  • Store     │     └──────────────────────────────┘ │
│  PhysioNet CSV       │  • Expose API│                                       │
│  (simulates          └──────┬───────┘                                       │
│   AD8232→ADC)              │                                                │
│                            ▼                                                │
│                     ┌──────────────┐                                        │
│                     │   SQLite /   │                                        │
│                     │   Database   │                                        │
│                     └──────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Pipeline

### 1. **Mock phase (current)**

| Step | Description |
|------|-------------|
| 1 | Load ECG from **MIT-BIH–style CSV** or **PhysioNet** export (360 Hz, one column). |
| 2 | **Simulated streaming**: send values in chunks (e.g. 180 samples) at ~2.78 ms per chunk to mimic 360 Hz. |
| 3 | **Ingestion**: `POST /api/v1/ecg/upload-chunk` or `POST /api/v1/ecg/upload-bulk`. |
| 4 | **Processing**: bandpass 0.5–40 Hz, R-peak detection, BPM, RR intervals, abnormality. |
| 5 | **Storage**: `ecg_sessions`, `ecg_readings`, `processed_results`, `alerts`. |
| 6 | **API**: waveform, health, results, alerts for frontend. |

### 2. **Hardware phase (later)**

Replace mock source with **ESP32**:

- **AD8232** → analog ECG → **ESP32 ADC** → digital stream.
- ESP32 sends over **Wi‑Fi** via **HTTP**, **WebSocket**, or **MQTT**.
- Payload format stays the same: `{ "session_id", "samples", "chunk_index" }` or equivalent.
- **No backend rewrite**: same `/upload-chunk` and processing.

---

## Component Roles

| Component | Role |
|-----------|------|
| **Mock data service** | Loads CSV / synthetic ECG; streams chunks; mimics AD8232 temporal behavior. |
| **ECG processor** | Baseline removal, bandpass, R-peaks, BPM, RR, abnormality. |
| **Routers** | REST: sessions, upload-chunk, upload-bulk, waveform, health, results, alerts, mock/sample. |
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
