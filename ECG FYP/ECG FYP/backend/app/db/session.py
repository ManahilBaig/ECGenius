"""Async database session and engine. Creates tables on startup."""
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import get_settings
from app.models.database import Base

_settings = get_settings()
connect_args = {"check_same_thread": False} if "sqlite" in _settings.DATABASE_URL else {}
engine = create_async_engine(
    _settings.DATABASE_URL,
    connect_args=connect_args,
    poolclass=StaticPool if "sqlite" in _settings.DATABASE_URL else None,
    echo=_settings.DEBUG,
)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_db() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        if "sqlite" in _settings.DATABASE_URL:
            rows = await conn.execute(text("PRAGMA table_info(ecg_sessions)"))
            existing_columns = {row[1] for row in rows.fetchall()}
            if "bpm" not in existing_columns:
                await conn.execute(text("ALTER TABLE ecg_sessions ADD COLUMN bpm FLOAT"))
            if "symptoms" not in existing_columns:
                await conn.execute(text("ALTER TABLE ecg_sessions ADD COLUMN symptoms TEXT"))
            if "created_by" not in existing_columns:
                await conn.execute(text("ALTER TABLE ecg_sessions ADD COLUMN created_by VARCHAR(255)"))


async def get_db() -> AsyncSession:
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()
