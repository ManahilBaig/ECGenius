# ECGenius App – What Each File Does

This document describes the role of each important file in the ECGenius application (Flutter app + FastAPI backend). Generated files (`build/`, `.dart_tool/`) are not listed.

---

## Flutter App (`ecgenius/`)

### Root

| File | Purpose |
|------|--------|
| **pubspec.yaml** | Flutter project config: app name, SDK, dependencies (flutter, http, provider, charts_flutter), and dev dependencies (flutter_test, flutter_lints). |

### `lib/` – Application code

| File | Purpose |
|------|--------|
| **main.dart** | App entry point. Runs `ECGeniusApp` and sets the home screen to `DashboardScreen`. |
| **config.dart** | Central app configuration: backend URL (host/port/scheme), API base path, BPM polling interval, timeouts, BPM thresholds (bradycardia/tachycardia), and sampling rate. Change `backendHost` here to point at your API server. |
| **dashboard_screen.dart** | Main dashboard UI: patient info, tabs (Monitoring / History), BPM card, ECG chart, BPM history chart, alert box. Creates/lists ECG sessions via API, polls live BPM during monitoring, and navigates to session detail. |
| **welcome_screen.dart** | Welcome/onboarding screen with “Get Started” button; used when the app shows the welcome overlay. |
| **session_detail_screen.dart** | Session detail screen: loads health status and waveform for one session via API, shows BPM, status, ECG chart, and alerts. |
| **widget_test.dart** | In-app widget test: smoke test that the dashboard loads and shows patient name, ID, tabs, and BPM. (Lives in `lib/`; standard tests are in `test/`.) |

### `lib/services/`

| File | Purpose |
|------|--------|
| **ecg_api_service.dart** | HTTP client for the backend. Defines models (e.g. `ECGSession`, `HealthStatus`, `Waveform`, `Alert`) and methods for: create/list/get sessions, get health (BPM/status), get waveform, get results, get alerts, bulk upload, and mock sample. Uses `config.dart` for base URL and timeouts. |

### `lib/widgets/`

| File | Purpose |
|------|--------|
| **ecg_chart.dart** | Widget that draws a live ECG-style waveform (e.g. simulated trace while monitoring). Updates on a timer when monitoring is active. |
| **bpm_card.dart** | Displays current BPM with color (green normal, blue low, orange high) and status text (Normal / Low / Elevated). |
| **bpm_chart.dart** | Line chart of BPM over time; appends current BPM periodically during monitoring and keeps a short history (e.g. last 60 points). |
| **alert_box.dart** | Shows an alert when BPM is outside 60–100 (low or elevated heart rate) with a short message and styling. Returns an empty box when in range. |

### `test/`

| File | Purpose |
|------|--------|
| **widget_test.dart** | Default Flutter test file (counter-style smoke test). Can be replaced or updated to match `main.dart` (e.g. `ECGeniusApp` / `DashboardScreen`). |

---

## Backend (`ECG FYP/ECG FYP/backend/`)

FastAPI app for ECG upload, processing, BPM, health status, waveform, and alerts. Uses async SQLAlchemy for DB; auth can use Firebase/Firestore.

### `app/` – Backend application root

| File | Purpose |
|------|--------|
| **main.py** | FastAPI app entry: creates app, CORS, lifespan (DB init), mounts auth and ECG routers under `/api/v1`, root route, and global `ValueError` handler. |
| **config.py** | Settings (from env/`.env`): app name, debug, ECG sample rate and bandpass, BPM thresholds, Firebase-related vars, API prefix, JWT secret/algorithm/token expiry. Used by other modules via `get_settings()`. |
| **auth.py** | JWT auth helpers: password hashing/verification (bcrypt), create/decode JWT access token. Used by auth router and protected routes. |

### `app/db/`

| File | Purpose |
|------|--------|
| **session.py** | Async DB engine and session factory (SQLAlchemy). Creates tables on startup (`init_db`). Provides `get_db()` dependency that yields an `AsyncSession`. Expects `DATABASE_URL` from settings (e.g. in `.env`). |
| **__init__.py** | Marks `db` as a package. |

### `app/models/`

| File | Purpose |
|------|--------|
| **database.py** | SQLAlchemy models: `User`, `ECGSession`, `ECGReading`, `ProcessedResult`, `Alert`. Defines tables and relationships for users, sessions, raw ECG chunks, processing results, and alerts. |
| **schemas.py** | Pydantic request/response schemas: e.g. `ECGChunkUpload`, `ECGBulkUpload`, `ECGSessionCreate`/`ECGSessionOut`, `ProcessedResultOut`, `HealthStatusOut`, `WaveformOut`, `AlertOut`, auth (e.g. `Token`, `UserCreate`, `UserOut`). Used for validation and API docs. |
| **__init__.py** | Marks `models` as a package. |

### `app/routers/`

| File | Purpose |
|------|--------|
| **ecg_router.py** | ECG REST API: create/list/get sessions, upload chunks/bulk, get health status, waveform, results, list alerts, mock sample. Uses DB session, ECG processor, alert service, mock data service, and ML service. |
| **auth_router.py** | Auth endpoints (e.g. register, login). Uses Firebase/Firestore for user storage and JWT (from `auth.py`) for tokens. |
| **__init__.py** | Marks `routers` as a package. |

### `app/services/`

| File | Purpose |
|------|--------|
| **ecg_processor.py** | ECG signal processing: validate input, bandpass filter, R-peak detection, BPM and RR intervals, abnormality classification (normal, bradycardia, tachycardia, irregular). Returns structured result (e.g. `ECGProcessedResult`) for storage/API. |
| **alert_service.py** | Creates and saves `Alert` records when processing detects an abnormality (bradycardia, tachycardia, irregular). Builds severity and message from abnormality type and BPM. |
| **mock_data_service.py** | Mock ECG data: load from MIT-BIH-style CSV (or generate synthetic), stream chunks for testing. Used by upload/mock endpoints to simulate ESP32 + AD8232 data. |
| **ml_service.py** | Loads trained cardiac model and scaler (e.g. from `cardiac_ml/`), runs feature-based ECG classification, returns prediction and confidence. Used when ML results are exposed via API. |
| **__init__.py** | Marks `services` as a package. |

### `app/__init__.py`

| File | Purpose |
|------|--------|
| **__init__.py** | Marks `app` as a Python package. |

---

## Summary

- **Flutter app**: `main.dart` → `DashboardScreen` and `config`; `ecg_api_service` talks to backend; widgets show BPM, ECG chart, and alerts.
- **Backend**: `main.py` mounts routers; `ecg_router` handles sessions, uploads, health, waveform, alerts; `ecg_processor` does signal processing; `alert_service` and `ml_service` add alerts and ML; `database` and `schemas` define data; `config` and `db/session` handle settings and DB.
