# ECGenius Architecture Notes

ECGenius has two main parts:

- **Flutter frontend** (`ecgenius/`): linear patient flow with ECG recording, symptom entry, and session history.
- **FastAPI backend** (`backend/app/`): ECG session persistence, sample ingestion, waveform/health/result APIs, and abnormality alerts.

Current patient flow:

1. Flutter creates an ECG session with `POST /api/v1/ecg/sessions`.
2. The ECG screen records a fixed 15-second session and displays live BPM/countdown.
3. The symptom entry screen finalizes the session with `POST /api/v1/ecg/sessions/{id}/complete`, saving raw samples, BPM, duration, and optional symptoms.
4. The history screen reads recorded sessions from `GET /api/v1/ecg/sessions`.

Important files:

- `ecgenius/lib/ecg_screen.dart`
- `ecgenius/lib/symptom_entry_screen.dart`
- `ecgenius/lib/patient_session_history_screen.dart`
- `ecgenius/lib/services/ecg_api_service.dart`
- `backend/app/routers/ecg_router.py`
- `backend/app/models/database.py`
- `backend/app/models/schemas.py`

Backend setup:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8001
```

Flutter setup:

```bash
cd ecgenius
flutter pub get
flutter run --dart-define=ECG_BACKEND_HOST=127.0.0.1
```

Use `10.0.2.2` for `ECG_BACKEND_HOST` when running on an Android emulator against a backend on the host machine.
