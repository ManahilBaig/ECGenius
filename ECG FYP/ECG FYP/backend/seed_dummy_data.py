"""
Seed existing ECG sessions with dummy data: synthetic waveform + processed results (BPM, status).
Run from backend directory: python seed_dummy_data.py
Uses the same DB as the FastAPI app (ecg_monitoring.db in backend/ or from config).
"""
import asyncio
import sys
from pathlib import Path

# Ensure backend is on path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import select
from app.config import get_settings
from app.db.session import async_session, init_db
from app.models.database import ECGSession, ECGReading, ProcessedResult
from app.services.ecg_processor import process_ecg
from app.services.mock_data_service import generate_synthetic_ecg_at_bpm


# Variety: normal, bradycardia, tachycardia, normal, slight brady
DEMO_BPM_LIST = [72, 55, 105, 88, 58]
SAMPLING_RATE = 360
DURATION_SECONDS = 10.0


async def seed_sessions():
    settings = get_settings()
    await init_db()

    async with async_session() as db:
        r = await db.execute(
            select(ECGSession).order_by(ECGSession.id.asc())
        )
        sessions = list(r.scalars().all())

        if not sessions:
            print("No sessions found. Create sessions from the app first (e.g. Start Monitoring).")
            return

        updated = 0
        for i, sess in enumerate(sessions):
            # Skip if already has processed result (already has dummy data)
            r2 = await db.execute(
                select(ProcessedResult).where(ProcessedResult.session_id == sess.id).limit(1)
            )
            if r2.scalar_one_or_none() is not None:
                continue

            bpm_target = DEMO_BPM_LIST[i % len(DEMO_BPM_LIST)]
            samples = generate_synthetic_ecg_at_bpm(SAMPLING_RATE, DURATION_SECONDS, bpm=bpm_target)

            # Add one ECG reading chunk
            rec = ECGReading(
                session_id=sess.id,
                samples=samples,
                chunk_index=0,
                sample_count=len(samples),
            )
            db.add(rec)
            await db.flush()

            # Process to get real BPM/abnormality from the signal
            res = process_ecg(
                samples,
                float(SAMPLING_RATE),
                settings.ECG_BANDPASS_LOW,
                settings.ECG_BANDPASS_HIGH,
                settings.BRADYCARDIA_THRESHOLD,
                settings.TACHYCARDIA_THRESHOLD,
            )

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

            # Mark session completed with duration
            sess.status = "completed"
            sess.total_duration_seconds = res.duration_seconds
            if sess.ended_at is None and sess.started_at:
                from datetime import timedelta
                sess.ended_at = sess.started_at + timedelta(seconds=res.duration_seconds)

            updated += 1
            print(f"  Session {sess.id}: BPM={res.bpm:.1f}, status={res.abnormality.value}")

        await db.commit()
        print(f"Seeded {updated} session(s) with dummy ECG and health data.")


if __name__ == "__main__":
    asyncio.run(seed_sessions())
