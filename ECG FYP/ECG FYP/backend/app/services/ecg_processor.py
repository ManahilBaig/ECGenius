"""
ECG Signal Processing Module

Processes raw ECG signals (simulating AD8232 → ESP32 ADC output) through:
1. Noise removal & baseline wander correction
2. Bandpass filtering (0.5–40 Hz)
3. R-peak detection
4. BPM, RR intervals, abnormality detection

Aligned with AD8232 characteristics:
- AD8232 outputs analog voltage; we assume 10–12 bit ADC on ESP32
- Sampling: 250–360 Hz (we use 360 Hz for MIT-BIH compatibility)
- Bandpass matches typical ECG clinical range
"""

import numpy as np
from scipy import signal
from scipy.signal import butter, filtfilt
from typing import List, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class AbnormalityType(str, Enum):
    """Detected ECG abnormalities."""
    NORMAL = "normal"
    BRADYCARDIA = "bradycardia"      # < 60 BPM
    TACHYCARDIA = "tachycardia"      # > 100 BPM
    IRREGULAR = "irregular_rhythm"   # High RR variability


@dataclass
class ECGProcessedResult:
    """Result of ECG processing for a session/segment."""
    bpm: float
    rr_intervals_ms: List[float]
    r_peaks_indices: List[int]
    r_peaks_timestamps_ms: List[float]
    abnormality: AbnormalityType
    filtered_signal: List[float]
    sampling_rate_hz: float
    duration_seconds: float
    num_beats: int
    mean_rr_ms: Optional[float] = None
    rr_std_ms: Optional[float] = None  # For irregularity detection


def _validate_input(ecg_raw: List[float], sampling_rate: float) -> None:
    """Validate ECG input. Raises ValueError on invalid/corrupted data."""
    if not ecg_raw or len(ecg_raw) < sampling_rate * 2:  # Min ~2 seconds
        raise ValueError("ECG segment too short for reliable analysis (min ~2 s)")
    if sampling_rate <= 0 or sampling_rate > 1000:
        raise ValueError("Invalid sampling rate (expected 250–1000 Hz)")
    arr = np.array(ecg_raw, dtype=float)
    if np.any(np.isnan(arr)) or np.any(np.isinf(arr)):
        raise ValueError("ECG data contains NaN or Inf (corrupted)")
    # Optional: clip extreme outliers that suggest sensor/ADC fault
    if np.abs(arr).max() > 1e6:
        raise ValueError("ECG values out of plausible range (possible ADC/sensor fault)")


def remove_baseline_wander(ecg: np.ndarray, sampling_rate: float, cutoff: float = 0.5) -> np.ndarray:
    """
    Remove baseline wander (slow drift) using high-pass filtering.
    
    Why: AD8232 can pick up respiration and body movement (0.1–0.5 Hz).
    High-pass with cutoff ~0.5 Hz removes this while keeping QRS (5–15 Hz).
    """
    nyquist = sampling_rate / 2
    normal_cutoff = cutoff / nyquist
    b, a = butter(2, normal_cutoff, btype="high", analog=False)
    return filtfilt(b, a, ecg)


def bandpass_filter(
    ecg: np.ndarray,
    sampling_rate: float,
    low: float = 0.5,
    high: float = 40.0
) -> np.ndarray:
    """
    Bandpass filter 0.5–40 Hz.
    
    Why (aligned with AD8232):
    - 0.5 Hz: Removes baseline wander (respiration, motion).
    - 40 Hz: Removes muscle noise, 50/60 Hz mains, RF from Wi-Fi/ESP32.
    - QRS complex: ~5–15 Hz; P/T waves: lower. 0.5–40 Hz preserves all diagnostic info.
    """
    nyquist = sampling_rate / 2
    low_n = low / nyquist
    high_n = min(high / nyquist, 0.99)
    b, a = butter(2, [low_n, high_n], btype="band")
    return filtfilt(b, a, ecg)


def detect_r_peaks(ecg: np.ndarray, sampling_rate: float) -> List[int]:
    """
    R-peak detection using derivative + moving window integration (Pan–Tompkins–style).
    
    Steps:
    1. Bandpass (already done) emphasizes QRS.
    2. Derivative enhances R-peak slope.
    3. Squaring emphasizes large slopes.
    4. Moving integration smooths and creates local maxima at R-peaks.
    5. Adaptive threshold to find peaks.
    
    Returns indices of R-peaks in the filtered signal.
    """
    # Differentiate to emphasize R-peak upstroke
    diff = np.diff(ecg.astype(float))
    diff = np.append(diff, 0)
    # Squaring
    squared = diff ** 2
    # Moving window integration (window ~0.08 s at 360 Hz ≈ 29 samples)
    win_len = max(int(0.08 * sampling_rate), 5)
    integrated = np.convolve(squared, np.ones(win_len) / win_len, mode="same")
    # Find peaks: minimal distance ≈ 0.4 s (refractory); 200 ms = 72 @ 360 Hz
    min_distance = int(0.4 * sampling_rate)
    peaks, _ = signal.find_peaks(integrated, distance=min_distance, prominence=np.percentile(integrated, 75) * 0.3)
    return peaks.tolist()


def compute_rr_and_bpm(
    r_peaks: List[int],
    sampling_rate: float
) -> Tuple[List[float], float, Optional[float], Optional[float]]:
    """
    Compute RR intervals (ms), mean BPM, mean RR, and RR std.
    
    BPM = 60000 / mean_RR_ms.
    RR_std used for irregular rhythm (high variability).
    """
    if len(r_peaks) < 2:
        return [], 0.0, None, None
    rr_ms = [1000.0 * (r_peaks[i + 1] - r_peaks[i]) / sampling_rate for i in range(len(r_peaks) - 1)]
    mean_rr = float(np.mean(rr_ms))
    rr_std = float(np.std(rr_ms))
    bpm = 60000.0 / mean_rr if mean_rr > 0 else 0.0
    return rr_ms, bpm, mean_rr, rr_std


def classify_abnormality(
    bpm: float,
    rr_std_ms: Optional[float],
    mean_rr_ms: Optional[float],
    brady_thresh: int = 60,
    tachy_thresh: int = 100
) -> AbnormalityType:
    """
    Classify rhythm: normal, bradycardia, tachycardia, or irregular.
    
    Irregular: RR standard deviation > 25% of mean RR (simple heuristic).
    """
    if bpm <= 0:
        return AbnormalityType.NORMAL
    if bpm < brady_thresh:
        return AbnormalityType.BRADYCARDIA
    if bpm > tachy_thresh:
        return AbnormalityType.TACHYCARDIA
    # Irregular: high RR variability
    if mean_rr_ms and rr_std_ms and mean_rr_ms > 0 and (rr_std_ms / mean_rr_ms) > 0.25:
        return AbnormalityType.IRREGULAR
    return AbnormalityType.NORMAL


def process_ecg(
    ecg_raw: List[float],
    sampling_rate: float,
    bandpass_low: float = 0.5,
    bandpass_high: float = 40.0,
    brady_thresh: int = 60,
    tachy_thresh: int = 100
) -> ECGProcessedResult:
    """
    Full ECG processing pipeline: validate → baseline → bandpass → R-peaks → BPM & RR → abnormality.
    
    Input: raw samples (ADC units or mV) as list/array.
    Output: ECGProcessedResult with BPM, RR, R-peaks, abnormality, filtered waveform.
    """
    _validate_input(ecg_raw, sampling_rate)
    arr = np.array(ecg_raw, dtype=float)
    # 1) Baseline wander removal (high-pass) — often embedded in bandpass, but explicit for clarity
    no_wander = remove_baseline_wander(arr, sampling_rate, cutoff=bandpass_low)
    # 2) Bandpass 0.5–40 Hz
    filtered = bandpass_filter(no_wander, sampling_rate, bandpass_low, bandpass_high)
    # 3) R-peak detection
    r_peaks = detect_r_peaks(filtered, sampling_rate)
    # 4) RR intervals and BPM
    rr_ms, bpm, mean_rr, rr_std = compute_rr_and_bpm(r_peaks, sampling_rate)
    # 5) Abnormality
    abn = classify_abnormality(bpm, rr_std, mean_rr, brady_thresh, tachy_thresh)
    # Timestamps of R-peaks in ms
    r_ts_ms = [1000.0 * i / sampling_rate for i in r_peaks]
    duration_s = len(arr) / sampling_rate
    return ECGProcessedResult(
        bpm=bpm,
        rr_intervals_ms=rr_ms,
        r_peaks_indices=r_peaks,
        r_peaks_timestamps_ms=r_ts_ms,
        abnormality=abn,
        filtered_signal=filtered.tolist(),
        sampling_rate_hz=sampling_rate,
        duration_seconds=duration_s,
        num_beats=len(r_peaks),
        mean_rr_ms=mean_rr,
        rr_std_ms=rr_std,
    )
