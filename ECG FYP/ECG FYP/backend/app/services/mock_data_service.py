"""
Mock ECG Data Service

Simulates ESP32 + AD8232 output by:
- Loading ECG from MIT-BIH–style CSV (or bundled sample)
- Streaming values in chunks at realistic sampling interval (~2.78–4 ms at 360/250 Hz)
- Emitting JSON payloads compatible with upload APIs

Mimics: AD8232 → ESP32 ADC → Wi-Fi transmission.
"""

import asyncio
import csv
import json
import os
from pathlib import Path
from typing import List, AsyncIterator, Optional, Tuple

# Default: look for CSV in project / mock_data. Format: one column of voltage or ADC values, optional header.
MOCK_DATA_DIR = Path(__file__).resolve().parents[3] / "mock_data"
SAMPLE_CSV = "mit_bih_sample.csv"  # We will provide a small sample; user can add full MIT-BIH exports.


def _find_sample_csv() -> Optional[Path]:
    p = MOCK_DATA_DIR / SAMPLE_CSV
    if p.exists():
        return p
    # Fallback: any CSV in mock_data
    if MOCK_DATA_DIR.exists():
        for f in MOCK_DATA_DIR.glob("*.csv"):
            return f
    return None


def load_ecg_from_csv(path: Optional[Path] = None) -> Tuple[List[float], int]:
    """
    Load ECG samples from CSV. Expects:
    - One column of numeric values (or first numeric column)
    - Optional header row
    - No timestamp required; we assume 360 Hz if not specified.

    Returns (samples, sampling_rate_hz). Default rate 360 for MIT-BIH compatibility.
    """
    p = path or _find_sample_csv()
    if not p or not p.exists():
        # Generate synthetic ECG for demo (simple sine-based QRS-like)
        return _generate_synthetic_ecg(360, 10), 360

    samples: List[float] = []
    with open(p, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            for cell in row:
                s = cell.strip()
                if not s or s.startswith("#"):
                    continue
                try:
                    samples.append(float(s))
                except ValueError:
                    pass
    if not samples:
        return _generate_synthetic_ecg(360, 10), 360
    return samples, 360


def _generate_synthetic_ecg(sampling_rate: int, duration_seconds: float) -> List[float]:
    """Synthetic ECG at ~75 BPM. See generate_synthetic_ecg_at_bpm for variable BPM."""
    return generate_synthetic_ecg_at_bpm(sampling_rate, duration_seconds, bpm=75)


def generate_synthetic_ecg_at_bpm(
    sampling_rate: int, duration_seconds: float, bpm: float = 75
) -> List[float]:
    """
    Simple synthetic ECG at a given BPM for demos.
    Not clinically accurate but produces detectable R-peaks for pipeline testing.
    """
    import math
    n = int(sampling_rate * duration_seconds)
    t = [i / sampling_rate for i in range(n)]
    f_hr = bpm / 60  # heart rate in Hz
    sig = [0.0] * n
    for i, ti in enumerate(t):
        sig[i] += 0.1 * math.sin(2 * math.pi * 0.2 * ti)
        r_times = [k / f_hr for k in range(int(duration_seconds * f_hr) + 1)]
        for rt in r_times:
            d = ti - rt
            sig[i] += 1.5 * math.exp(-(d * 15) ** 2)
    return sig


async def get_mock_chunk_iterator(
    samples: List[float],
    sampling_rate: int,
    chunk_size: int = 180,
    delay_seconds: Optional[float] = None
) -> AsyncIterator[List[float]]:
    """
    Async iterator that yields chunks of `chunk_size` samples.
    If delay_seconds is set, waits to simulate real-time streaming
    (chunk_size/sampling_rate seconds per chunk).
    """
    interval = (chunk_size / sampling_rate) if delay_seconds is None else delay_seconds
    for i in range(0, len(samples), chunk_size):
        chunk = samples[i : i + chunk_size]
        if not chunk:
            break
        yield chunk
        if interval > 0:
            await asyncio.sleep(interval)


async def stream_mock_ecg_as_json(
    session_id: int,
    chunk_index_start: int = 0,
    sampling_rate: int = 360,
    chunk_size: int = 180,
    max_chunks: Optional[int] = 50,
    simulate_realtime: bool = True
) -> AsyncIterator[str]:
    """
    Yields JSON strings compatible with ECGChunkUpload semantics.
    Each: {"session_id": int, "samples": [...], "chunk_index": int}.
    """
    samples, _ = load_ecg_from_csv()
    if max_chunks:
        total = min(len(samples), chunk_size * max_chunks)
        samples = samples[:total]
    delay = (chunk_size / sampling_rate) if simulate_realtime else None
    idx = chunk_index_start
    async for chunk in get_mock_chunk_iterator(samples, sampling_rate, chunk_size, delay):
        obj = {"session_id": session_id, "samples": chunk, "chunk_index": idx}
        yield json.dumps(obj)
        idx += 1


def get_bundled_sample_path() -> Optional[Path]:
    return _find_sample_csv()
