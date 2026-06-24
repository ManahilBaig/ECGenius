#!/bin/bash
# Quick setup script for ECGenius - Run this first!

echo "==========================================="
echo "ECGenius Quick Start Script"
echo "==========================================="

# Check Python
echo ""
echo "1. Checking Python..."
python --version

# Check Flutter
echo ""
echo "2. Checking Flutter..."
flutter --version

# Install backend dependencies
echo ""
echo "3. Installing backend dependencies..."
cd "ECG FYP/ECG FYP/backend"
pip install -r requirements.txt

echo ""
echo "==========================================="
echo "Setup Complete!"
echo ""
echo "TO RUN THE SYSTEM:"
echo ""
echo "Terminal 1 (Backend):"
echo "  cd \"ECG FYP/backend\""
echo "  uvicorn app.main:app --reload --host 0.0.0.0"
echo ""
echo "Terminal 2 (Frontend):"
echo "  cd ecgenius"
echo "  flutter run"
echo ""
echo "Then open http://localhost:8000/docs to see the API"
echo "==========================================="
