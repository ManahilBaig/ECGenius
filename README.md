# ECGenius - ECG Monitoring & Analysis System

An IoT-based ECG monitoring system that captures real-time heart data, analyzes it using Machine Learning (Random Forest Classifier), and detects arrhythmias.

## Features

- **BLE ECG Recording** - Connect to ESP32 + AD8232 sensor via Bluetooth Low Energy
- **Demo Mode** - Realistic ECG playback from backend for testing without hardware
- **ML Classification** - Random Forest model detects Normal Sinus Rhythm, Atrial Fibrillation, Arrhythmia, and Congestive Heart Failure
- **Real-time BPM** - Live heart rate display with realistic fluctuation during recording
- **Session History** - View past recordings with ML predictions and waveform data
- **PDF Reports** - Export session reports via system share sheet
- **User Authentication** - Register/login with JWT-based backend auth
- **Termux Ready** - Backend runs on Android phone via Termux Ubuntu

## Project Structure

- **ecgenius/** - Flutter mobile application (Frontend)
- **ECG FYP/backend/** - Python FastAPI server (Backend)
- **cardiac_ml/** - Machine Learning model training pipeline

## System Requirements

- **Python 3.10+**
- **Flutter SDK 3.0+**
- **Git**
- **Android 6.0+** (for BLE support)

## Setup Instructions

### 1. Backend Setup

```bash
cd "ECG FYP/ECG FYP/backend"

# Create virtual environment (optional)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install fastapi uvicorn sqlalchemy aiosqlite pydantic-settings python-jose passlib python-multipart numpy scipy joblib scikit-learn

# Run the server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Backend runs at `http://localhost:8000` with API docs at `/docs`.

### 2. Frontend Setup

```bash
cd ecgenius

# Install dependencies
flutter pub get

# Build APK
flutter build apk --release --dart-define=ECG_BACKEND_HOST=127.0.0.1
```

For phone-only use (Termux backend): `ECG_BACKEND_HOST=127.0.0.1`
For PC backend: `ECG_BACKEND_HOST=192.168.x.x` (your PC's IP)

### 3. Termux Setup (Phone-Only Backend)

```bash
# Install Ubuntu in Termux
pkg install proot-distro
proot-distro install ubuntu
proot-distro login ubuntu

# Install Python and dependencies
apt update && apt install python3-pip -y
pip install fastapi uvicorn sqlalchemy aiosqlite pydantic-settings python-jose passlib python-multipart numpy scipy joblib scikit-learn

# Run backend
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Machine Learning

The system uses a **Random Forest Classifier** trained on ECG data to detect:

| Class | Description |
|-------|-------------|
| NSR | Normal Sinus Rhythm |
| AFF | Atrial Fibrillation/Flutter |
| ARR | Other Arrhythmia |
| CHF | Congestive Heart Failure |

- **Accuracy**: 97.08%
- **F1 Score**: 97.07% (weighted)
- **Training Samples**: 1,200 (300 per class)
- **Features**: 54 ECG segment features

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/login` | Login (OAuth2 form) |
| POST | `/api/v1/ecg/sessions` | Create ECG session |
| POST | `/api/v1/ecg/sessions/{id}/complete` | Complete session with samples |
| GET | `/api/v1/ecg/sessions/{id}/ml-prediction` | Get ML classification |
| GET | `/api/v1/ecg/demo-ecg` | Get demo ECG signal |
| GET | `/api/v1/ecg/sessions/{id}/waveform` | Get ECG waveform |

## Hardware

- **ESP32** microcontroller
- **AD8232** ECG sensor
- Electrodes (3-lead)

## Tech Stack

- **Frontend**: Flutter, Dart
- **Backend**: FastAPI, SQLAlchemy, SQLite
- **ML**: scikit-learn, NumPy, SciPy
- **Auth**: JWT (python-jose), passlib
