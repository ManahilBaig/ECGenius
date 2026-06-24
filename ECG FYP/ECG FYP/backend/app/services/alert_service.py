"""
Alert Service: creates Alert records when ECG processing detects abnormalities.
"""

from app.models.database import Alert, ECGSession
from app.services.ecg_processor import AbnormalityType
from sqlalchemy.ext.asyncio import AsyncSession


def _severity(abn: AbnormalityType) -> str:
    if abn == AbnormalityType.BRADYCARDIA or abn == AbnormalityType.TACHYCARDIA:
        return "high"
    if abn == AbnormalityType.IRREGULAR:
        return "medium"
    return "low"


def _message(abn: AbnormalityType, bpm: float) -> str:
    if abn == AbnormalityType.BRADYCARDIA:
        return f"Bradycardia detected: heart rate {bpm:.1f} BPM (below 60 BPM)."
    if abn == AbnormalityType.TACHYCARDIA:
        return f"Tachycardia detected: heart rate {bpm:.1f} BPM (above 100 BPM)."
    if abn == AbnormalityType.IRREGULAR:
        return f"Irregular rhythm detected at {bpm:.1f} BPM (elevated RR variability)."
    return "Normal sinus rhythm."


async def create_alert_if_abnormal(
    session: AsyncSession,
    session_id: int,
    abnormality: AbnormalityType,
    bpm: float
) -> Alert | None:
    """Create and persist an Alert when abnormality is not NORMAL."""
    if abnormality == AbnormalityType.NORMAL:
        return None
    alert = Alert(
        session_id=session_id,
        alert_type=abnormality.value,
        severity=_severity(abnormality),
        message=_message(abnormality, bpm),
        bpm_at_alert=bpm,
    )
    session.add(alert)
    await session.flush()
    await session.refresh(alert)
    return alert
