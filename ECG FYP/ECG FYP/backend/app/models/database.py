"""
SQLAlchemy Database Models

Tables:
- users: Authentication and user identity
- ecg_sessions: A single recording session (session-based storage for ECG)
- ecg_readings: Raw ECG samples (chunked per session for scalability)
- processed_results: BPM, RR, abnormality per session/segment
- alerts: Detected abnormalities and notifications

Why session-based storage:
- ECG is inherently temporal: one "recording" = one session (e.g., 30 s, 5 min).
- Enables: get all data for a session, replay, compare sessions, audit.
- Chunking readings avoids huge rows; we store segments (e.g., 1–5 s) or full session.
"""

from datetime import datetime
from sqlalchemy import Column, Integer, Float, String, DateTime, ForeignKey, Text, Boolean, JSON
from sqlalchemy.orm import relationship, declarative_base

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    sessions = relationship("ECGSession", back_populates="user")


class ECGSession(Base):
    """
    One ECG recording session.
    e.g., "Morning check 2024-01-15", "Stress test", or a continuous 5-min stream.
    """
    __tablename__ = "ecg_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    name = Column(String(255), nullable=True)  # e.g., "Morning reading"
    sampling_rate_hz = Column(Float, nullable=False)  # 250–360 typical for AD8232
    source = Column(String(50), default="app")
    started_at = Column(DateTime, default=datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)
    total_duration_seconds = Column(Float, nullable=True)
    bpm = Column(Float, nullable=True)
    symptoms = Column(Text, nullable=True)
    status = Column(String(20), default="recording")  # recording | completed | failed

    user = relationship("User", back_populates="sessions")
    readings = relationship("ECGReading", back_populates="session", cascade="all, delete-orphan")
    results = relationship("ProcessedResult", back_populates="session", cascade="all, delete-orphan")
    alerts = relationship("Alert", back_populates="session", cascade="all, delete-orphan")


class ECGReading(Base):
    """
    Raw ECG samples for a session.
    Stored in chunks to avoid enormous rows. Each chunk = a segment (e.g., 1–5 s of samples).
    """
    __tablename__ = "ecg_readings"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("ecg_sessions.id"), nullable=False, index=True)
    # Store as JSON array of floats for flexibility (SQLite-friendly). For large scale, consider binary/blob.
    samples = Column(JSON, nullable=False)  # List[float]
    chunk_index = Column(Integer, nullable=False)  # Order of chunk in session
    start_time_offset_ms = Column(Float, nullable=True)  # Ms from session start
    sample_count = Column(Integer, nullable=False)

    session = relationship("ECGSession", back_populates="readings")


class ProcessedResult(Base):
    """
    Results of ECG processing for a session (or a segment within it).
    One row per processing run: e.g., one per session when session ends, or per sliding window.
    """
    __tablename__ = "processed_results"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("ecg_sessions.id"), nullable=False, index=True)
    bpm = Column(Float, nullable=False)
    mean_rr_ms = Column(Float, nullable=True)
    rr_std_ms = Column(Float, nullable=True)
    rr_intervals_ms = Column(JSON, nullable=True)  # List[float]
    abnormality = Column(String(50), nullable=False)  # normal | bradycardia | tachycardia | irregular_rhythm
    num_beats = Column(Integer, nullable=False)
    duration_seconds = Column(Float, nullable=False)
    # Optional: store filtered waveform excerpt for frontend (or fetch from readings + reprocess)
    processed_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("ECGSession", back_populates="results")


class Alert(Base):
    """
    Alerts generated when abnormality is detected or threshold crossed.
    """
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("ecg_sessions.id"), nullable=False, index=True)
    alert_type = Column(String(50), nullable=False)  # bradycardia | tachycardia | irregular_rhythm
    severity = Column(String(20), default="medium")  # low | medium | high
    message = Column(Text, nullable=True)
    bpm_at_alert = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("ECGSession", back_populates="alerts")
