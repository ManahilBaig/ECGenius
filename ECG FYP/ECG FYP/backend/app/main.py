"""
ECG Monitoring System - FastAPI Application

REST API for ECG upload, processing, BPM, health status, waveform, and alerts.
Designed for mock data first; hardware-ready for ESP32 + AD8232.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db.session import init_db
from app.routers.ecg_router import router as ecg_router

try:
    from app.routers.auth_router import router as auth_router
    _has_auth = True
except ImportError:
    _has_auth = False
    print("WARNING: google-cloud-firestore not installed. Auth endpoints disabled.")

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title=settings.APP_NAME,
    description="Real-time ECG Monitoring Backend (ESP32 + AD8232). Mock-ready; hardware-ready.",
    version="1.0.0",
    lifespan=lifespan,
)

# Enable CORS for Flutter web and other clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    return JSONResponse(
        status_code=400,
        content={"detail": str(exc)},
    )


if _has_auth:
    app.include_router(auth_router, prefix=settings.API_V1_PREFIX)
app.include_router(ecg_router, prefix=settings.API_V1_PREFIX)


@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "docs": "/docs",
        "api": settings.API_V1_PREFIX,
    }
