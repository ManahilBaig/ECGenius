"""
Configuration for ECG Monitoring System Backend.
Uses environment variables with sensible defaults for development.
"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment."""
    
    # Application
    APP_NAME: str = "ECG Monitoring System"
    DEBUG: bool = False
    
    # ECG Processing (aligned with AD8232)
    ECG_SAMPLE_RATE: int = 360  # Hz - matches MIT-BIH, close to AD8232 250–360 Hz
    ECG_BANDPASS_LOW: float = 0.5   # Hz - remove baseline wander
    ECG_BANDPASS_HIGH: float = 40.0  # Hz - remove high-frequency noise
    
    # Heart Rate Thresholds (BPM)
    BRADYCARDIA_THRESHOLD: int = 60   # < 60 BPM
    TACHYCARDIA_THRESHOLD: int = 100  # > 100 BPM
    
    # Firebase
    FIREBASE_PROJECT_ID: str = "your-firebase-project-id"
    FIREBASE_PRIVATE_KEY_ID: str = "your-private-key-id"
    FIREBASE_PRIVATE_KEY: str = "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n"
    FIREBASE_CLIENT_EMAIL: str = "firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com"
    FIREBASE_CLIENT_ID: str = "your-client-id"
    FIREBASE_AUTH_URI: str = "https://accounts.google.com/o/oauth2/auth"
    FIREBASE_TOKEN_URI: str = "https://oauth2.googleapis.com/token"
    FIREBASE_AUTH_PROVIDER_X509_CERT_URL: str = "https://www.googleapis.com/oauth2/v1/certs"
    FIREBASE_CLIENT_X509_CERT_URL: str = "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-xxxxx%40your-project.iam.gserviceaccount.com"
    
    # Database (SQLite default for development)
    DATABASE_URL: str = "sqlite+aiosqlite:///./ecg_monitoring.db"

    # API
    API_V1_PREFIX: str = "/api/v1"
    
    # Auth (basic - for academic use)
    SECRET_KEY: str = "change-in-production-academic-use-only"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours
    
    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()
