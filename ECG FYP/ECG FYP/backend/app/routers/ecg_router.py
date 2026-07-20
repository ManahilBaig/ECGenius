"""
ECG REST API: uploads, sessions, waveform, health status, results, alerts.
"""

import numpy as np
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.database import ECGSession, ECGReading, ProcessedResult, Alert
from app.models.schemas import (
    ECGChunkUpload,
    ECGBulkUpload,
    ECGSessionCreate,
    ECGSessionComplete,
    ECGSessionOut,
    ProcessedResultOut,
    HealthStatusOut,
    WaveformOut,
    WaveformPoint,
    AlertOut,
)
from app.services.ecg_processor import process_ecg, generate_demo_ecg
from app.services.alert_service import create_alert_if_abnormal
from app.services.ml_service import ml_service
from app.services.ecg_feature_extraction import extract_ml_features, extract_segment_features_from_waveform
from app.config import get_settings

router = APIRouter(prefix="/ecg", tags=["ecg"])
_settings = get_settings()


def _gather_samples(db_session: ECGSession, readings: list) -> list:
    """Collect and order all samples from ECGReading chunks."""
    ordered = sorted(readings, key=lambda r: r.chunk_index)
    out = []
    for r in ordered:
        out.extend(r.samples)
    return out


async def _get_or_404_session(session_id: int, db: AsyncSession):
    r = await db.execute(
        select(ECGSession).where(ECGSession.id == session_id)
    )
    s = r.scalar_one_or_none()
    if not s:
        raise HTTPException(404, "Session not found")
    return s


# ---- Session ----
@router.post("/sessions", response_model=ECGSessionOut)
async def create_session(
    data: ECGSessionCreate,
    db: AsyncSession = Depends(get_db),
):
    s = ECGSession(
        name=data.name,
        sampling_rate_hz=data.sampling_rate_hz,
        source=data.source,
        created_by=data.created_by,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return s


@router.get("/sessions", response_model=list[ECGSessionOut])
async def list_sessions(
    skip: int = 0,
    limit: int | None = Query(None, ge=1),
    user_email: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
):
    query = select(ECGSession).order_by(ECGSession.started_at.desc()).offset(skip)
    if user_email:
        from sqlalchemy import or_
        query = query.where(
            or_(
                ECGSession.created_by == user_email,
                ECGSession.created_by.is_(None),
            )
        )
    if limit is not None:
        query = query.limit(limit)
    r = await db.execute(query)
    return list(r.scalars().all())


@router.get("/sessions/{session_id}", response_model=ECGSessionOut)
async def get_session(session_id: int, db: AsyncSession = Depends(get_db)):
    return await _get_or_404_session(session_id, db)


@router.delete("/sessions/{session_id}")
async def delete_session(session_id: int, db: AsyncSession = Depends(get_db)):
    sess = await _get_or_404_session(session_id, db)
    await db.delete(sess)
    await db.commit()
    return {"message": f"Session {session_id} deleted"}


@router.post("/sessions/{session_id}/complete", response_model=ECGSessionOut)
async def complete_session(
    session_id: int,
    data: ECGSessionComplete,
    db: AsyncSession = Depends(get_db),
):
    sess = await _get_or_404_session(session_id, db)
    await db.execute(delete(ECGReading).where(ECGReading.session_id == session_id))
    await db.execute(delete(ProcessedResult).where(ProcessedResult.session_id == session_id))
    await db.execute(delete(Alert).where(Alert.session_id == session_id))

    reading = ECGReading(
        session_id=session_id,
        samples=data.samples,
        chunk_index=0,
        start_time_offset_ms=0,
        sample_count=len(data.samples),
    )
    db.add(reading)

    result = process_ecg(
        data.samples,
        sess.sampling_rate_hz,
        _settings.ECG_BANDPASS_LOW,
        _settings.ECG_BANDPASS_HIGH,
        _settings.BRADYCARDIA_THRESHOLD,
        _settings.TACHYCARDIA_THRESHOLD,
    )
    duration_seconds = data.total_duration_seconds or result.duration_seconds
    saved_bpm = float(data.final_bpm)
    processed = ProcessedResult(
        session_id=session_id,
        bpm=saved_bpm,
        mean_rr_ms=result.mean_rr_ms,
        rr_std_ms=result.rr_std_ms,
        rr_intervals_ms=result.rr_intervals_ms,
        abnormality=result.abnormality.value,
        num_beats=result.num_beats,
        duration_seconds=duration_seconds,
    )
    db.add(processed)
    await create_alert_if_abnormal(db, session_id, result.abnormality, saved_bpm)

    sess.bpm = saved_bpm
    sess.symptoms = data.symptoms
    sess.total_duration_seconds = duration_seconds
    sess.ended_at = datetime.utcnow()
    sess.status = "completed"
    if data.name:
        sess.name = data.name

    await db.commit()
    await db.refresh(sess)
    return sess


# ---- Upload ----
@router.post("/upload-chunk")
async def upload_chunk(
    data: ECGChunkUpload,
    db: AsyncSession = Depends(get_db),
):
    """Append a chunk of ECG samples from the active recorder."""
    sess = await _get_or_404_session(data.session_id, db)
    rec = ECGReading(
        session_id=data.session_id,
        samples=data.samples,
        chunk_index=data.chunk_index,
        start_time_offset_ms=data.start_time_offset_ms,
        sample_count=len(data.samples),
    )
    db.add(rec)
    await db.commit()
    return {"session_id": data.session_id, "chunk_index": data.chunk_index, "samples_received": len(data.samples)}


@router.post("/upload-bulk")
async def upload_bulk(
    data: ECGBulkUpload,
    db: AsyncSession = Depends(get_db),
):
    """
    Upload a full segment: creates a session, stores samples, runs processing,
    saves result and alerts.
    """
    sess = ECGSession(
        user_id=data.user_id,
        name=data.session_name,
        sampling_rate_hz=data.sampling_rate_hz,
        source="uploaded",
        status="completed",
    )
    db.add(sess)
    await db.flush()
    # Single chunk
    rec = ECGReading(
        session_id=sess.id,
        samples=data.samples,
        chunk_index=0,
        sample_count=len(data.samples),
    )
    db.add(rec)
    # Process
    res = process_ecg(
        data.samples,
        data.sampling_rate_hz,
        _settings.ECG_BANDPASS_LOW,
        _settings.ECG_BANDPASS_HIGH,
        _settings.BRADYCARDIA_THRESHOLD,
        _settings.TACHYCARDIA_THRESHOLD,
    )
    # Result
    pr = ProcessedResult(
        session_id=sess.id,
        bpm=res.bpm,
        mean_rr_ms=res.mean_rr_ms,
        rr_std_ms=res.rr_std_ms,
        rr_intervals_ms=res.rr_intervals_ms,
        abnormality=res.abnormality.value,
        num_beats=res.num_beats,
        duration_seconds=res.duration_seconds,
    )
    db.add(pr)
    await create_alert_if_abnormal(db, sess.id, res.abnormality, res.bpm)
    sess.total_duration_seconds = res.duration_seconds
    sess.ended_at = sess.started_at  # simplified
    await db.commit()
    await db.refresh(sess)
    return {
        "session_id": sess.id,
        "bpm": res.bpm,
        "abnormality": res.abnormality.value,
        "num_beats": res.num_beats,
        "duration_seconds": res.duration_seconds,
    }


# ---- Waveform ----
@router.get("/sessions/{session_id}/waveform", response_model=WaveformOut)
async def get_waveform(
    session_id: int,
    filtered: bool = Query(True, description="Return filtered (bandpass) signal"),
    db: AsyncSession = Depends(get_db),
):
    """Fetch ECG waveform for frontend plot. Filtered = bandpass 0.5–40 Hz."""
    sess = await _get_or_404_session(session_id, db)
    r = await db.execute(
        select(ECGReading).where(ECGReading.session_id == session_id).order_by(ECGReading.chunk_index)
    )
    readings = list(r.scalars().all())
    if not readings:
        # Return empty waveform for sessions without ECG data
        return WaveformOut(session_id=session_id, sampling_rate_hz=sess.sampling_rate_hz or 360, points=[], is_filtered=filtered)
    raw = _gather_samples(sess, readings)
    sr = sess.sampling_rate_hz
    if filtered:
        proc = process_ecg(
            raw, sr,
            _settings.ECG_BANDPASS_LOW,
            _settings.ECG_BANDPASS_HIGH,
            _settings.BRADYCARDIA_THRESHOLD,
            _settings.TACHYCARDIA_THRESHOLD,
        )
        sig = proc.filtered_signal
    else:
        sig = raw
    points = [WaveformPoint(t_ms=1000.0 * i / sr, value=float(v)) for i, v in enumerate(sig)]
    return WaveformOut(session_id=session_id, sampling_rate_hz=sr, points=points, is_filtered=filtered)


# ---- Health ----
@router.get("/sessions/{session_id}/health", response_model=HealthStatusOut)
async def get_health(session_id: int, db: AsyncSession = Depends(get_db)):
    """BPM and health status. Uses latest ProcessedResult or runs processing if none."""
    sess = await _get_or_404_session(session_id, db)
    r = await db.execute(
        select(ProcessedResult).where(ProcessedResult.session_id == session_id).order_by(ProcessedResult.processed_at.desc()).limit(1)
    )
    pr = r.scalar_one_or_none()
    if pr:
        return HealthStatusOut(
            bpm=pr.bpm,
            status=pr.abnormality,
            num_beats=pr.num_beats,
            duration_seconds=pr.duration_seconds,
            mean_rr_ms=pr.mean_rr_ms,
        )
    # No result: get raw and process
    rr = await db.execute(select(ECGReading).where(ECGReading.session_id == session_id).order_by(ECGReading.chunk_index))
    readings = list(rr.scalars().all())
    if not readings:
        if sess.bpm is not None:
            return HealthStatusOut(
                bpm=sess.bpm,
                status="recording",
                num_beats=0,
                duration_seconds=sess.total_duration_seconds or 0,
                mean_rr_ms=None,
            )
        raise HTTPException(404, "No ECG data to compute health status")
    raw = _gather_samples(sess, readings)
    res = process_ecg(
        raw, sess.sampling_rate_hz,
        _settings.ECG_BANDPASS_LOW,
        _settings.ECG_BANDPASS_HIGH,
        _settings.BRADYCARDIA_THRESHOLD,
        _settings.TACHYCARDIA_THRESHOLD,
    )
    return HealthStatusOut(
        bpm=res.bpm,
        status=res.abnormality.value,
        num_beats=res.num_beats,
        duration_seconds=res.duration_seconds,
        mean_rr_ms=res.mean_rr_ms,
    )


# ---- ML Classification ----
@router.get("/sessions/{session_id}/ml-prediction")
async def get_ml_prediction(session_id: int, db: AsyncSession = Depends(get_db)):
    """
    Get ML classification for a session from its processed result.
    Uses RR/HRV from rr_intervals and P/QRS/T segment features from waveform when available.
    """
    sess = await _get_or_404_session(session_id, db)

    # For demo sessions, return pre-defined predictions
    if sess.source == "demo":
        demo_predictions = {
            "Ali": {"prediction": "NSR", "confidence": 0.94, "probabilities": {"AFF": 0.02, "ARR": 0.03, "CHF": 0.01, "NSR": 0.94}},
            "Zimal": {"prediction": "NSR", "confidence": 0.91, "probabilities": {"AFF": 0.03, "ARR": 0.04, "CHF": 0.02, "NSR": 0.91}},
            "Anika": {"prediction": "NSR", "confidence": 0.88, "probabilities": {"AFF": 0.04, "ARR": 0.05, "CHF": 0.03, "NSR": 0.88}},
            "Shahnaz": {"prediction": "ARR", "confidence": 0.82, "probabilities": {"AFF": 0.06, "ARR": 0.82, "CHF": 0.07, "NSR": 0.05}},
        }
        pred = demo_predictions.get(sess.name, {"prediction": "NSR", "confidence": 0.90, "probabilities": {"AFF": 0.03, "ARR": 0.03, "CHF": 0.04, "NSR": 0.90}})
        return {
            "session_id": session_id,
            "prediction": pred["prediction"],
            "confidence": pred["confidence"],
            "probabilities": pred["probabilities"],
            "error": None,
        }

    r = await db.execute(
        select(ProcessedResult)
        .where(ProcessedResult.session_id == session_id)
        .order_by(ProcessedResult.processed_at.desc())
        .limit(1)
    )
    pr = r.scalar_one_or_none()
    if not pr:
        return {
            "session_id": session_id,
            "prediction": None,
            "confidence": 0.0,
            "probabilities": None,
            "error": "No processed ECG data for this session",
        }
    rr_list = pr.rr_intervals_ms if isinstance(pr.rr_intervals_ms, list) else None
    features = extract_ml_features(
        bpm=float(pr.bpm),
        mean_rr_ms=float(pr.mean_rr_ms) if pr.mean_rr_ms is not None else None,
        rr_std_ms=float(pr.rr_std_ms) if pr.rr_std_ms is not None else None,
        rr_intervals_ms=rr_list,
        num_beats=int(pr.num_beats),
        duration_seconds=float(pr.duration_seconds) if pr.duration_seconds is not None else None,
    )
    # Enrich with P/QRS/T segment features from raw waveform when available
    rr_readings = await db.execute(
        select(ECGReading)
        .where(ECGReading.session_id == session_id)
        .order_by(ECGReading.chunk_index)
    )
    readings = list(rr_readings.scalars().all())
    if readings:
        try:
            raw = _gather_samples(sess, readings)
            sr = float(sess.sampling_rate_hz)
            proc = process_ecg(
                raw,
                sr,
                _settings.ECG_BANDPASS_LOW,
                _settings.ECG_BANDPASS_HIGH,
                _settings.BRADYCARDIA_THRESHOLD,
                _settings.TACHYCARDIA_THRESHOLD,
            )
            seg = extract_segment_features_from_waveform(
                np.asarray(proc.filtered_signal, dtype=float),
                proc.r_peaks_indices,
                sr,
            )
            for k, v in seg.items():
                features[k] = v
        except Exception:
            pass  # keep RR/HRV-only features if waveform extraction fails
    result = ml_service.predict_ecg_class(features)
    return {
        "session_id": session_id,
        "prediction": result.get("prediction"),
        "confidence": result.get("confidence", 0.0),
        "probabilities": result.get("probabilities"),
        "error": result.get("error"),
    }


@router.post("/sessions/{session_id}/classify")
async def classify_ecg(session_id: int, features: dict, db: AsyncSession = Depends(get_db)):
    """
    Classify ECG signal using ML model.
    Expects a dictionary of ECG features matching the training data format.
    """
    await _get_or_404_session(session_id, db)

    # Get ML prediction
    prediction = ml_service.predict_ecg_class(features)

    return {
        "session_id": session_id,
        "prediction": prediction
    }


# ---- Processed results ----
@router.get("/sessions/{session_id}/results", response_model=list[ProcessedResultOut])
async def get_results(session_id: int, db: AsyncSession = Depends(get_db)):
    await _get_or_404_session(session_id, db)
    r = await db.execute(
        select(ProcessedResult).where(ProcessedResult.session_id == session_id).order_by(ProcessedResult.processed_at.desc())
    )
    return list(r.scalars().all())


# ---- Alerts ----
@router.get("/alerts", response_model=list[AlertOut])
async def list_alerts(
    session_id: int | None = Query(None),
    skip: int = 0,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
):
    q = select(Alert).order_by(Alert.created_at.desc())
    if session_id is not None:
        q = q.where(Alert.session_id == session_id)
    r = await db.execute(q.offset(skip).limit(limit))
    return list(r.scalars().all())


# ---- Demo ----
@router.get("/demo-ecg")
async def get_demo_ecg():
    """
    Returns a realistic synthetic ECG signal for demo purposes.
    ~5400 samples at 360 Hz (15 seconds) with random BPM and morphology.
    """
    bpm = float(np.random.choice([68, 70, 72, 74, 76, 78]))
    samples = generate_demo_ecg(
        duration_seconds=15.0,
        sampling_rate=360.0,
        bpm=bpm,
    )
    return {
        "samples": samples,
        "sampling_rate_hz": 360.0,
        "duration_seconds": 15.0,
        "bpm": bpm,
        "num_samples": len(samples),
    }
