# ECGenius - ECG Monitoring & Analysis System

An IoT-based ECG monitoring system that captures real-time heart data, analyzes it using Machine Learning (Random Forest Classifier), and detects arrhythmias.

## Project Structure
- **ecgenius/**: Flutter mobile application (Frontend).
- **ECG FYP/backend/**: Python FastAPI server (Backend).
- **cardiac_ml/**: Machine Learning model training pipeline.

## System Requirements
- **Python 3.10+**
- **Flutter SDK**
- **Git**

## Setup Instructions

### 1. Backend Setup
The backend handles ECG signal processing and ML classification.

1.  Navigate to the backend directory:
    ```bash
    cd "ECG FYP/ECG FYP/backend"
    ```
2.  Create a virtual environment (optional but recommended):
    ```bash
    python -m venv venv
    source venv/bin/activate  # On Windows: venv\Scripts\activate
    ```
3.  Install dependencies:
    ```bash
    pip install -r requirements.txt
    ```
4.  Run the server:
    ```bash
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
    ```

### 2. Frontend Setup
The mobile app visualizes the ECG waveform and health alerts.

1.  Navigate to the app directory:
    ```bash
    cd ecgenius
    ```
2.  Install packages:
    ```bash
    flutter pub get
    ```
3.  Connect your Android device via USB (ensure USB Debugging is on).
4.  Run the app:
    ```bash
    flutter run
    ```

## Machine Learning
The system uses a **Random Forest Classifier** to detect:
- Normal Sinus Rhythm (NSR)
- Atrial Fibrillation (AFF)
- Congestive Heart Failure (CHF)
- Arrhythmia (ARR)
