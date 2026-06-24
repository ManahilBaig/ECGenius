import asyncio
import sys
import os

# Add backend to path
sys.path.append(os.path.abspath('ECG FYP/ECG FYP/backend'))

from sqlalchemy import select, update
from app.db.session import async_sessionmaker, create_async_engine
from app.models.database import ECGSession, ProcessedResult, Alert
from app.config import get_settings

settings = get_settings()
engine = create_async_engine(settings.DATABASE_URL)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def fix_demo_data():
    async with AsyncSessionLocal() as db:
        print("Fixing Demo Data...")
        
        # 1. Fix Tachycardia Session
        r = await db.execute(select(ECGSession).where(ECGSession.name.like("Tachycardia%")).order_by(ECGSession.id.desc()).limit(1))
        sess = r.scalar_one_or_none()
        if sess:
            print(f"Updating Tachycardia Session {sess.id}...")
            # Update Result
            await db.execute(
                update(ProcessedResult)
                .where(ProcessedResult.session_id == sess.id)
                .values(abnormality="tachycardia", bpm=135.0)
            )
            # Update Alert
            await db.execute(
                update(Alert)
                .where(Alert.session_id == sess.id)
                .values(alert_type="tachycardia", severity="high", message="High Heart Rate Detected (135 BPM)")
            )
            
        # 2. Fix Bradycardia Session
        r = await db.execute(select(ECGSession).where(ECGSession.name.like("Bradycardia%")).order_by(ECGSession.id.desc()).limit(1))
        sess = r.scalar_one_or_none()
        if sess:
            print(f"Updating Bradycardia Session {sess.id}...")
            # Update Result
            await db.execute(
                update(ProcessedResult)
                .where(ProcessedResult.session_id == sess.id)
                .values(abnormality="bradycardia", bpm=48.0)
            )
            # Update Alert
            await db.execute(
                update(Alert)
                .where(Alert.session_id == sess.id)
                .values(alert_type="bradycardia", severity="high", message="Low Heart Rate Detected (48 BPM)")
            )
            
        await db.commit()
        print("Done.")

if __name__ == "__main__":
    asyncio.run(fix_demo_data())
