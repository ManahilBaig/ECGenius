# ECG Monitoring System - AI Agent Instructions

## Project Overview

**ECGenius** is a hardware-ready ECG monitoring system with:
- **Backend** (FastAPI): Real-time ECG ingestion, signal processing, abnormality detection
- **Frontend** (Flutter): Dashboard for BPM display, waveform visualization, alerts, history
- **Data Flow**: Mock CSV data (MIT-BIH) → API upload → processing → DB storage → frontend display

### Key Context
- **Current Phase**: Mock data pipeline (validates algorithms before ESP32+AD8232 hardware arrives)
- **Hardware Target**: ESP32 + AD8232 ECG sensor (250–360 Hz sampling) ← will replace mock later
- **Sampling Rate**: 360 Hz (MIT-BIH standard; configured in [config.py](../backend/app/config.py))
- **Processing**: Bandpass 0.5–40 Hz, R-peak detection, BPM, RR intervals, abnormality classification

## Architecture Essentials

### Data Flow (Mock Phase)
1. **Ingestion**: Mock CSV or Flutter mock API → `POST /api/v1/ecg/upload-bulk` or `/upload-chunk`
2. **Processing**: [ECGProcessor](../backend/app/services/ecg_processor.py) validates, filters, detects R-peaks, computes BPM
3. **Storage**: Session-based DB ([database.py](../backend/app/models/database.py)): users → sessions → readings (chunks) → results → alerts
4. **API**: [ecg_router.py](../backend/app/routers/ecg_router.py) exposes waveform, health, results, alerts
5. **Frontend**: Flutter dashboard fetches from `/sessions/{id}/health`, `/waveform`, `/alerts`

### Session-Based Architecture (Critical Pattern)
**Why**: ECG is inherently temporal. One "recording" = one session (30s–5min).
- Each upload creates/appends to an `ECGSession` record
- Raw samples stored as JSON chunks in `ECGReading` (one chunk ~180 samples @ 360 Hz)
- `ProcessedResult` holds BPM, RR, abnormality (one result per session/segment)
- **Workflow**: Create session → upload chunks → process → store results → expose via API

See [SYSTEM_ARCHITECTURE.md](../docs/SYSTEM_ARCHITECTURE.md) for detailed flow.

## Key Project Patterns

### 1. **Async-First Database** ([db/session.py](../backend/app/db/session.py))
- **Engine**: SQLAlchemy AsyncSession with SQLite + StaticPool (avoids "database is locked")
- **Startup**: `init_db()` in FastAPI lifespan creates all tables
- **Dependency**: Router functions use `db: AsyncSession = Depends(get_db)`
- **Pattern**: Always `await db.commit()` after mutations; use `select()` + `db.execute()`

### 2. **Pydantic Data Contracts** ([models/schemas.py](../backend/app/models/schemas.py))
- **Upload payloads**: `ECGChunkUpload` (streaming) or `ECGBulkUpload` (batch)
- **Responses**: `ECGSessionOut`, `ProcessedResultOut`, `HealthStatusOut`, `WaveformOut`
- **Field validators**: Enforce numeric validation on samples, length limits (1–500k), rate (100–1000 Hz)

### 3. **Signal Processing** ([services/ecg_processor.py](../backend/app/services/ecg_processor.py))
- **Validation first**: Rejects < 2s data, NaN/Inf, out-of-range values → raises `ValueError` (→ 400 HTTP)
- **Pipeline**: Remove baseline wander (high-pass 0.5 Hz) → bandpass (0.5–40 Hz) → detect R-peaks (scipy.signal.find_peaks) → compute BPM, RR intervals
- **Abnormality classification**: `NORMAL` | `BRADYCARDIA` (< 60 BPM) | `TACHYCARDIA` (> 100 BPM) | `IRREGULAR` (high RR std)
- **Config-driven**: Thresholds in [config.py](../backend/app/config.py) (e.g., `BRADYCARDIA_THRESHOLD=60`)

### 4. **Alert Generation** ([services/alert_service.py](../backend/app/services/alert_service.py))
- **Automatic**: After processing, `create_alert_if_abnormal()` creates DB record if abnormality ≠ NORMAL
- **Severity mapping**: BRADY/TACHY → "high", IRREGULAR → "medium", NORMAL → none (no record)
- **Message template**: Includes BPM and condition type; called from `ecg_router.py` upload endpoints

### 5. **Mock Data** ([services/mock_data_service.py](../backend/app/services/mock_data_service.py))
- **Source**: `mock_data/mit_bih_sample.csv` (360 Hz, single numeric column)
- **Endpoint**: `GET /api/v1/ecg/mock/sample` returns 1–2 seconds of samples
- **Integration**: Upload-bulk or chunk endpoints accept mock data seamlessly
- **Future swap**: Replace with ESP32 HTTP/WebSocket/MQTT without changing API contract

## Development Workflows

### Running the Backend
```bash
cd "backend"
uvicorn app.main:app --reload --host 0.0.0.0
# API: http://localhost:8000
# Docs: http://localhost:8000/docs (interactive)
```

### Database Reset
```bash
# Delete ecg_monitoring.db, then restart server (init_db in lifespan recreates)
rm ecg_monitoring.db  # or equivalent on Windows
```

### Testing Mock Upload (curl / Postman)
```bash
# 1. Get mock sample
curl http://localhost:8000/api/v1/ecg/mock/sample

# 2. Upload bulk
curl -X POST http://localhost:8000/api/v1/ecg/upload-bulk \
  -H "Content-Type: application/json" \
  -d '{"samples": [72, 75, 78, ...], "sampling_rate_hz": 360}'

# 3. Check results
curl http://localhost:8000/api/v1/ecg/sessions
curl http://localhost:8000/api/v1/ecg/sessions/1/health
curl http://localhost:8000/api/v1/ecg/sessions/1/waveform
```

### Flutter Frontend
- **Entry**: [main.dart](../ecgenius/main.dart) → [dashboard_screen.dart](../ecgenius/dashboard_screen.dart)
- **Mocking**: [mock_api.dart](../ecgenius/services/mock_api.dart) mimics backend responses
- **Widgets**: [ecg_chart.dart](../ecgenius/widgets/ecg_chart.dart), [bpm_card.dart](../ecgenius/widgets/bpm_card.dart), [alert_box.dart](../ecgenius/widgets/alert_box.dart)
- **No HTTP yet**: Currently local mock; refactor to call actual backend when ready

## Configuration & Environment

### Key Settings ([config.py](../backend/app/config.py))
- `ECG_SAMPLE_RATE`: 360 Hz (align with AD8232 and MIT-BIH)
- `ECG_BANDPASS_LOW` / `HIGH`: 0.5–40 Hz (removes baseline wander & high-freq noise)
- `BRADYCARDIA_THRESHOLD`: 60 BPM
- `TACHYCARDIA_THRESHOLD`: 100 BPM
- `DATABASE_URL`: SQLite by default; swap to PostgreSQL + async driver for scale
- `SECRET_KEY`: Change in production

### Environment File
Copy `.env.example` → `.env` and override as needed. Loaded via Pydantic Settings.

## Common Tasks

### Adding a New ECG Endpoint
1. **Schema**: Add request/response to [schemas.py](../backend/app/models/schemas.py)
2. **Router**: Add function to [ecg_router.py](../backend/app/routers/ecg_router.py) with `@router.get/post`
3. **DB query**: Use async session + SQLAlchemy `select()` + `db.execute()`
4. **Test**: Hit `/docs` or use curl/Postman

### Modifying Signal Processing
1. **Edit**: [ecg_processor.py](../backend/app/services/ecg_processor.py)
2. **Thresholds**: Update [config.py](../backend/app/config.py) if adding new parameters
3. **Test**: Call `process_ecg()` locally or via POST `/upload-bulk`
4. **Validate**: Confirm BPM, RR, abnormality in ProcessedResult

### Switching Mock Data
1. **File**: Replace/add CSV to `mock_data/` (360 Hz, numeric column)
2. **Code**: [mock_data_service.py](../backend/app/services/mock_data_service.py) auto-detects `*.csv`
3. **No API change**: Endpoint `/mock/sample` works with any CSV

## Documentation References
- [SYSTEM_ARCHITECTURE.md](../docs/SYSTEM_ARCHITECTURE.md): High-level design, data flow
- [SIGNAL_PROCESSING.md](../docs/SIGNAL_PROCESSING.md): Filtering, R-peak, BPM algorithms
- [DATABASE_DESIGN.md](../docs/DATABASE_DESIGN.md): Schema, relationships
- [API_SPECIFICATION.md](../docs/API_SPECIFICATION.md): Endpoint reference
- [HARDWARE_TRANSITION.md](../docs/HARDWARE_TRANSITION.md): Replacing mock with ESP32 (HTTP/WebSocket/MQTT)

## Do's & Don'ts

✅ **Do**
- Check [config.py](../backend/app/config.py) before hardcoding thresholds
- Validate input early (Pydantic schemas, `_validate_input` in processor)
- Use async/await consistently; never block with sync I/O
- Return descriptive error messages (400 for bad data, 404 for missing session)
- Test against mock sample before hardware

❌ **Don't**
- Hardcode sampling rate; use `sampling_rate_hz` from request or config
- Bypass Pydantic validation for user input
- Use sync database calls (not compatible with async FastAPI)
- Assume session exists without `_get_or_404_session` pattern
- Store unprocessed binary data without chunking strategy

## Escalation Points
- **Hardware transition**: See [HARDWARE_TRANSITION.md](../docs/HARDWARE_TRANSITION.md)—API compatible but source field changes
- **Database scaling**: Move from SQLite to PostgreSQL; consider blob/binary for large waveforms
- **Real-time streaming**: Add WebSocket or MQTT for live waveform + alerts
- **Abnormality algorithms**: Consult [SIGNAL_PROCESSING.md](../docs/SIGNAL_PROCESSING.md) for feature engineering
