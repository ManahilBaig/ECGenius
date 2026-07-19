"""
Seeds 4 demo ECG sessions on startup.
Clears existing sessions and creates fresh ones with realistic data.
"""

import numpy as np
from datetime import datetime, timedelta
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import ECGSession, ECGReading, ProcessedResult, Alert


def _generate_nsr_ecg(duration_s: float = 15.0, sr: float = 360.0, bpm: float = 72.0, seed: int = 42) -> list:
    """Generate a realistic Normal Sinus Rhythm ECG."""
    np.random.seed(seed)
    n = int(duration_s * sr)
    t = np.arange(n) / sr
    beat_int = 60.0 / bpm
    beat_len = int(beat_int * sr)
    samples = np.zeros(n)

    for beat_start in range(0, n, beat_len):
        end = min(beat_start + beat_len, n)
        bl = end - beat_start
        bp = np.arange(bl) / sr

        # P wave
        p_center = int(0.12 * sr)
        if p_center < bl:
            p_w = int(0.04 * sr)
            p_start = max(0, p_center - p_w)
            p_end = min(bl, p_center + p_w)
            samples[beat_start + p_start:beat_start + p_end] += 0.12 * np.sin(
                np.linspace(0, np.pi, p_end - p_start)
            ) * np.exp(-0.5 * ((np.arange(p_end - p_start) - (p_end - p_start) // 2) / (p_w / 2.5)) ** 2)

        # QRS complex
        qrs_center = int(0.22 * sr)
        q_start = qrs_center - int(0.02 * sr)
        r_end = qrs_center + int(0.025 * sr)
        s_end = qrs_center + int(0.045 * sr)
        if q_start < bl:
            qs = max(0, q_start)
            qe = min(bl, qrs_center)
            samples[beat_start + qs:beat_start + qe] -= 0.15 * np.sin(np.linspace(0, np.pi, qe - qs))
        if r_end < bl:
            rs = max(0, qrs_center)
            re = min(bl, r_end)
            samples[beat_start + rs:beat_start + re] += 1.0 * np.sin(np.linspace(0, np.pi, re - rs))
        if s_end < bl:
            ss = max(0, r_end)
            se = min(bl, s_end)
            samples[beat_start + ss:beat_start + se] -= 0.2 * np.sin(np.linspace(0, np.pi, se - ss))

        # T wave
        t_center = int(0.42 * sr)
        t_w = int(0.07 * sr)
        if t_center < bl:
            ts = max(0, t_center - t_w)
            te = min(bl, t_center + t_w)
            samples[beat_start + ts:beat_start + te] += 0.25 * np.sin(np.linspace(0, np.pi, te - ts))

    # Add noise
    baseline = 0.03 * np.sin(2 * np.pi * 0.15 * t)
    noise = 0.015 * np.random.randn(n)
    from scipy.signal import butter, filtfilt
    b, a = butter(2, 50.0 / (sr / 2), btype='low')
    noise = filtfilt(b, a, noise)
    samples += baseline + noise

    mx = np.max(np.abs(samples))
    if mx > 0:
        samples = samples / mx
    return samples.tolist()


def _generate_arrhythmia_ecg(duration_s: float = 15.0, sr: float = 360.0, bpm: float = 85.0, seed: int = 99) -> list:
    """Generate an ECG with irregular rhythm (arrhythmia)."""
    np.random.seed(seed)
    n = int(duration_s * sr)
    t = np.arange(n) / sr
    samples = np.zeros(n)

    # Irregular RR intervals
    np.random.seed(seed)
    base_rr = 60.0 / bpm
    rr_intervals = base_rr + np.random.uniform(-0.15, 0.15, size=int(duration_s / base_rr) + 5)
    beat_times = np.cumsum(rr_intervals)
    beat_times = beat_times[beat_times < duration_s]

    for bt in beat_times:
        idx = int(bt * sr)
        if idx + int(0.6 * sr) >= n:
            break

        # P wave (sometimes missing in arrhythmia)
        if np.random.random() > 0.3:
            p_center = idx + int(0.1 * sr)
            p_w = int(0.035 * sr)
            ps = max(0, p_center - p_w)
            pe = min(n, p_center + p_w)
            amplitude = np.random.uniform(0.05, 0.15)
            samples[ps:pe] += amplitude * np.sin(np.linspace(0, np.pi, pe - ps))

        # QRS (variable width)
        qrs_center = idx + int(0.2 * sr)
        qrs_w = int(np.random.uniform(0.07, 0.12) * sr)
        r_peak = qrs_center
        r_amp = np.random.uniform(0.7, 1.0)
        qs = max(0, r_peak - int(0.02 * sr))
        re = min(n, r_peak + int(0.03 * sr))
        samples[qs:re] += r_amp * np.sin(np.linspace(0, np.pi, re - qs))
        s_end = min(n, re + int(0.02 * sr))
        samples[re:s_end] -= 0.25 * np.sin(np.linspace(0, np.pi, s_end - re))

        # T wave (variable)
        t_center = idx + int(0.38 * sr)
        t_w = int(0.06 * sr)
        ts = max(0, t_center - t_w)
        te = min(n, t_center + t_w)
        t_amp = np.random.uniform(0.15, 0.3)
        samples[ts:te] += t_amp * np.sin(np.linspace(0, np.pi, te - ts))

    # Add baseline wander and noise
    baseline = 0.04 * np.sin(2 * np.pi * 0.2 * t) + 0.02 * np.sin(2 * np.pi * 0.08 * t)
    noise = 0.02 * np.random.randn(n)
    from scipy.signal import butter, filtfilt
    b, a = butter(2, 50.0 / (sr / 2), btype='low')
    noise = filtfilt(b, a, noise)
    samples += baseline + noise

    mx = np.max(np.abs(samples))
    if mx > 0:
        samples = samples / mx
    return samples.tolist()


DEMO_SESSIONS = [
    {
        "name": "Ali",
        "bpm": 72.0,
        "age_range": "18-29",
        "symptoms": "Age Range: 18-29\nSymptoms: None",
        "prediction": "NSR",
        "confidence": 0.94,
        "seed": 42,
        "generator": "nsr",
        "bpm_display": 72,
    },
    {
        "name": "Zimal",
        "bpm": 70.0,
        "age_range": "18-29",
        "symptoms": "Age Range: 18-29\nSymptoms: Mild chest discomfort during exercise",
        "prediction": "NSR",
        "confidence": 0.91,
        "seed": 77,
        "generator": "nsr",
        "bpm_display": 70,
    },
    {
        "name": "Anika",
        "bpm": 74.0,
        "age_range": "18-29",
        "symptoms": "Age Range: 18-29\nSymptoms: Occasional dizziness, fatigue",
        "prediction": "NSR",
        "confidence": 0.88,
        "seed": 123,
        "generator": "nsr",
        "bpm_display": 74,
    },
    {
        "name": "Shahnaz",
        "bpm": 85.0,
        "age_range": "45-59",
        "symptoms": "Age Range: 45-59\nSymptoms: Shortness of breath, palpitations, chest tightness",
        "prediction": "ARR",
        "confidence": 0.82,
        "seed": 99,
        "generator": "arrhythmia",
        "bpm_display": 85,
    },
]


async def seed_demo_sessions(db: AsyncSession) -> None:
    """Clear existing sessions and seed 4 demo sessions."""
    # Clear existing data
    await db.execute(delete(Alert))
    await db.execute(delete(ProcessedResult))
    await db.execute(delete(ECGReading))
    await db.execute(delete(ECGSession))
    await db.commit()

    base_time = datetime(2025, 7, 19, 10, 15, 0)
    time_offsets = [0, 135, 270, 465]  # minutes from 10:15

    for i, demo in enumerate(DEMO_SESSIONS):
        session_time = base_time + timedelta(minutes=time_offsets[i])

        sr = 360.0
        duration = 15.0
        n_samples = int(sr * duration)

        if demo["generator"] == "arrhythmia":
            raw = _generate_arrhythmia_ecg(duration, sr, demo["bpm"], demo["seed"])
        else:
            raw = _generate_nsr_ecg(duration, sr, demo["bpm"], demo["seed"])

        # Ensure correct length
        if len(raw) > n_samples:
            raw = raw[:n_samples]
        elif len(raw) < n_samples:
            raw.extend([0.0] * (n_samples - len(raw)))

        session = ECGSession(
            name=demo["name"],
            sampling_rate_hz=sr,
            source="demo",
            status="completed",
            started_at=session_time,
            ended_at=session_time + timedelta(seconds=duration),
            total_duration_seconds=duration,
            bpm=float(demo["bpm_display"]),
            symptoms=demo["symptoms"],
        )
        db.add(session)
        await db.flush()

        reading = ECGReading(
            session_id=session.id,
            samples=raw,
            chunk_index=0,
            start_time_offset_ms=0,
            sample_count=len(raw),
        )
        db.add(reading)

        processed = ProcessedResult(
            session_id=session.id,
            bpm=float(demo["bpm_display"]),
            mean_rr_ms=60000.0 / demo["bpm"],
            rr_std_ms=25.0 if demo["prediction"] == "NSR" else 80.0,
            rr_intervals_ms=[60000.0 / demo["bpm"]] * int(duration * demo["bpm"] / 60),
            abnormality="normal" if demo["prediction"] == "NSR" else "irregular_rhythm",
            num_beats=int(duration * demo["bpm"] / 60),
            duration_seconds=duration,
            processed_at=session_time,
        )
        db.add(processed)

    await db.commit()
    print(f"Seeded {len(DEMO_SESSIONS)} demo sessions")
