"""
Pydantic Schemas for API request/response validation.
"""

from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, field_validator


# ---- ECG Data (simulates ESP32 / mock) ----
class ECGChunkUpload(BaseModel):
    """Payload for uploading a chunk of ECG samples (ESP32 or mock streaming)."""
    session_id: int
    samples: List[float] = Field(..., min_length=1, max_length=10000)
    chunk_index: int = Field(..., ge=0)
    start_time_offset_ms: Optional[float] = None

    @field_validator("samples")
    @classmethod
    def samples_numeric(cls, v: List[float]) -> List[float]:
        if any(not isinstance(x, (int, float)) for x in v):
            raise ValueError("All samples must be numeric")
        return [float(x) for x in v]


class ECGBulkUpload(BaseModel):
    """Upload a full segment of ECG for a new or existing session (mock/batch)."""
    samples: List[float] = Field(..., min_length=1, max_length=500_000)  # ~23 min @ 360 Hz
    sampling_rate_hz: float = Field(360.0, ge=100, le=1000)
    session_name: Optional[str] = None
    user_id: Optional[int] = None


# ---- Sessions ----
class ECGSessionCreate(BaseModel):
    name: Optional[str] = None
    sampling_rate_hz: float = Field(360.0, ge=100, le=1000)
    source: str = Field("mock", pattern="^(mock|esp32_http|esp32_websocket|esp32_mqtt)$")


class ECGSessionOut(BaseModel):
    id: int
    user_id: Optional[int]
    name: Optional[str]
    sampling_rate_hz: float
    source: str
    started_at: datetime
    ended_at: Optional[datetime]
    total_duration_seconds: Optional[float]
    status: str

    class Config:
        from_attributes = True


# ---- Processed results ----
class ProcessedResultOut(BaseModel):
    id: int
    session_id: int
    bpm: float
    mean_rr_ms: Optional[float]
    rr_std_ms: Optional[float]
    abnormality: str
    num_beats: int
    duration_seconds: float
    processed_at: datetime

    class Config:
        from_attributes = True


class HealthStatusOut(BaseModel):
    """BPM and health status for dashboard."""
    bpm: float
    status: str  # normal | bradycardia | tachycardia | irregular_rhythm
    num_beats: int
    duration_seconds: float
    mean_rr_ms: Optional[float] = None


# ---- Waveform (for frontend plot) ----
class WaveformPoint(BaseModel):
    t_ms: float
    value: float


class WaveformOut(BaseModel):
    session_id: int
    sampling_rate_hz: float
    points: List[WaveformPoint]
    is_filtered: bool = True


# ---- Alerts ----
class AlertOut(BaseModel):
    id: int
    session_id: int
    alert_type: str
    severity: str
    message: Optional[str]
    bpm_at_alert: Optional[float]
    created_at: datetime

    class Config:
        from_attributes = True


# ---- Auth (basic) ----
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserCreate(BaseModel):
    email: str
    password: str
    full_name: Optional[str] = None


class UserOut(BaseModel):
    id: int
    email: str
    full_name: Optional[str]
    is_active: bool

    class Config:
        from_attributes = True
