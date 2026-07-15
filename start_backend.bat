@echo off
cd /d "F:\ECG App\New folder (2)\ECGenius\ECG FYP\ECG FYP\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001
pause
