"""
Extract ML model features from processed ECG (ProcessedResult) and optional raw signal.
Computes RR/HRV features from rr_intervals_ms; P/QRS/T segment and angle features from waveform.
"""

import math
import numpy as np
from typing import List, Dict, Optional, Tuple

# Feature names expected by the cardiac ML model (same order as ml_service.py)
ML_FEATURE_NAMES = [
    "hbpermin", "Pseg", "PQseg", "QRSseg", "QRseg", "QTseg", "RSseg", "STseg", "Tseg",
    "PTseg", "ECGseg", "QRtoQSdur", "RStoQSdur", "RRmean", "PPmean", "PQdis",
    "PonQdis", "PRdis", "PonRdis", "PSdis", "PonSdis", "PTdis", "PonTdis", "PToffdis",
    "QRdis", "QSdis", "QTdis", "QToffdis", "RSdis", "RTdis", "RToffdis", "STdis",
    "SToffdis", "PonToffdis", "PonPQang", "PQRang", "QRSang", "RSTang", "STToffang",
    "RRTot", "NNTot", "SDRR", "IBIM", "IBISD", "SDSD", "RMSSD", "QRSarea", "QRSperi",
    "PQslope", "QRslope", "RSslope", "STslope", "NN50", "pNN50",
]


def _safe_mean(arr: np.ndarray) -> float:
    if arr.size == 0:
        return 0.0
    return float(np.nanmean(arr))


def _safe_std(arr: np.ndarray) -> float:
    if arr.size < 2:
        return 0.0
    return float(np.nanstd(arr))


def _compute_rmssd(rr_ms: List[float]) -> float:
    """Root mean square of successive RR differences (ms)."""
    if not rr_ms or len(rr_ms) < 2:
        return 0.0
    arr = np.array(rr_ms, dtype=float)
    diffs = np.diff(arr)
    return float(np.sqrt(np.nanmean(diffs ** 2)))


def _compute_nn50_pnn50(rr_ms: List[float]) -> tuple:
    """Count of successive RR differences > 50 ms, and pNN50 (%)."""
    if not rr_ms or len(rr_ms) < 2:
        return 0.0, 0.0
    arr = np.array(rr_ms, dtype=float)
    diffs = np.abs(np.diff(arr))
    nn50 = int(np.sum(diffs > 50.0))
    n = len(diffs)
    pnn50 = (nn50 / n * 100.0) if n > 0 else 0.0
    return nn50, pnn50


def _compute_sdsd(rr_ms: List[float]) -> float:
    """Standard deviation of successive RR differences (ms)."""
    if not rr_ms or len(rr_ms) < 3:
        return 0.0
    arr = np.array(rr_ms, dtype=float)
    diffs = np.diff(arr)
    return _safe_std(diffs)


def _ms(samples: int, sampling_rate: float) -> float:
    return 1000.0 * samples / sampling_rate


def _delineate_beat(
    ecg: np.ndarray,
    r_idx: int,
    sampling_rate: float,
) -> Tuple[Optional[int], Optional[int], Optional[int], Optional[int]]:
    """
    Find Q, S, P, T indices around one R-peak.
    Q: min in [R - 50ms, R], S: min in [R, R + 50ms], T: max in [S+50ms, S+350ms], P: max in [R-250ms, R-60ms].
    """
    n = len(ecg)
    sr = sampling_rate
    # windows in samples (typical QRS ~80-120 ms)
    win_q = int(0.05 * sr)  # 50 ms before R
    win_s = int(0.05 * sr)  # 50 ms after R
    win_t_len = int(0.35 * sr)  # T search 50-350 ms after S
    win_t_start = int(0.05 * sr)
    win_p_start = int(0.25 * sr)  # P search 250-60 ms before R
    win_p_end = int(0.06 * sr)

    q_idx, s_idx, p_idx, t_idx = None, None, None, None

    # Q: minimum in segment before R
    i0 = max(0, r_idx - win_q)
    seg = ecg[i0 : r_idx + 1]
    if len(seg) > 0:
        q_idx = i0 + int(np.argmin(seg))

    # S: minimum in segment after R
    i1 = min(n, r_idx + win_s + 1)
    seg = ecg[r_idx : i1]
    if len(seg) > 0:
        s_idx = r_idx + int(np.argmin(seg))

    if s_idx is not None:
        # T: maximum in window after S
        t_start = min(n, s_idx + win_t_start)
        t_end = min(n, s_idx + win_t_len)
        if t_end > t_start:
            seg = ecg[t_start:t_end]
            t_idx = t_start + int(np.argmax(seg))

    # P: maximum in window before QRS (P wave usually positive)
    p_start = max(0, r_idx - win_p_start)
    p_end = max(0, r_idx - win_p_end)
    if p_end > p_start:
        seg = ecg[p_start:p_end]
        if len(seg) > 0:
            p_idx = p_start + int(np.argmax(seg))

    return q_idx, s_idx, p_idx, t_idx


def extract_segment_features_from_waveform(
    filtered_ecg: np.ndarray,
    r_peaks_indices: List[int],
    sampling_rate: float,
) -> Dict[str, float]:
    """
    Extract P/QRS/T segment durations, distances, slopes, and angles from filtered ECG.
    Averages over all beats; returns dict with keys matching ML_FEATURE_NAMES (segment/angle only).
    """
    out: Dict[str, float] = {}
    sr = float(sampling_rate)
    ecg = np.asarray(filtered_ecg, dtype=float)
    n = len(ecg)

    qrs_durs: List[float] = []
    qr_durs: List[float] = []
    rs_durs: List[float] = []
    qt_durs: List[float] = []
    st_durs: List[float] = []
    pq_durs: List[float] = []
    p_durs: List[float] = []
    t_durs: List[float] = []

    qrs_areas: List[float] = []
    qr_slopes: List[float] = []
    rs_slopes: List[float] = []
    st_slopes: List[float] = []
    pq_slopes: List[float] = []

    for r_idx in r_peaks_indices:
        if r_idx < 0 or r_idx >= n:
            continue
        q_idx, s_idx, p_idx, t_idx = _delineate_beat(ecg, r_idx, sr)

        if q_idx is not None and s_idx is not None and s_idx > q_idx:
            qrs_durs.append(_ms(s_idx - q_idx, sr))
            qr_durs.append(_ms(r_idx - q_idx, sr))
            rs_durs.append(_ms(s_idx - r_idx, sr))
            # QRS area (sum of absolute amplitude over segment)
            qrs_areas.append(float(np.sum(np.abs(ecg[q_idx : s_idx + 1])) / sr * 1000))  # scale
            if ecg[q_idx] != ecg[r_idx]:
                qr_slopes.append((float(ecg[r_idx]) - float(ecg[q_idx])) / max((r_idx - q_idx) / sr, 1e-6))
            if ecg[s_idx] != ecg[r_idx]:
                rs_slopes.append((float(ecg[s_idx]) - float(ecg[r_idx])) / max((s_idx - r_idx) / sr, 1e-6))

        if q_idx is not None and t_idx is not None and t_idx > q_idx:
            qt_durs.append(_ms(t_idx - q_idx, sr))
        if s_idx is not None and t_idx is not None and t_idx > s_idx:
            st_durs.append(_ms(t_idx - s_idx, sr))
            if ecg[t_idx] != ecg[s_idx]:
                st_slopes.append((float(ecg[t_idx]) - float(ecg[s_idx])) / max((t_idx - s_idx) / sr, 1e-6))
        if p_idx is not None and q_idx is not None and q_idx > p_idx:
            pq_durs.append(_ms(q_idx - p_idx, sr))
            if ecg[q_idx] != ecg[p_idx]:
                pq_slopes.append((float(ecg[q_idx]) - float(ecg[p_idx])) / max((q_idx - p_idx) / sr, 1e-6))
        # P and T duration: approximate 60 ms and 80 ms if we have bounds
        if p_idx is not None:
            p_durs.append(60.0)  # typical P duration
        if t_idx is not None:
            t_durs.append(80.0)  # typical T duration

    def avg(x: List[float]) -> float:
        return float(np.mean(x)) if x else 0.0

    # Segment durations (ms)
    out["QRSseg"] = avg(qrs_durs)
    out["QRseg"] = avg(qr_durs)
    out["RSseg"] = avg(rs_durs)
    out["QTseg"] = avg(qt_durs)
    out["STseg"] = avg(st_durs)
    out["PQseg"] = avg(pq_durs)
    out["Pseg"] = avg(p_durs) if p_durs else 0.0
    out["Tseg"] = avg(t_durs) if t_durs else 0.0
    out["PTseg"] = avg(p_durs) + avg(pq_durs) + avg(qrs_durs) if (p_durs or pq_durs or qrs_durs) else 0.0
    out["ECGseg"] = avg(qrs_durs) + avg(st_durs) + avg(qt_durs)  # simplified

    # Distances (same as durations for these)
    out["QRtoQSdur"] = avg(qr_durs)
    out["RStoQSdur"] = avg(rs_durs)
    out["PQdis"] = avg(pq_durs)
    out["PonQdis"] = avg(pq_durs)
    out["PRdis"] = avg(pq_durs) + avg(qr_durs) * 0.5
    out["PonRdis"] = out["PRdis"]
    out["PSdis"] = out["PRdis"] + avg(rs_durs)
    out["PonSdis"] = out["PSdis"]
    out["PTdis"] = avg(pq_durs) + avg(qrs_durs)
    out["PonTdis"] = out["PTdis"] + avg(st_durs) * 0.5
    out["PToffdis"] = out["PTdis"] + avg(st_durs)
    out["QRdis"] = avg(qr_durs)
    out["QSdis"] = avg(qrs_durs)
    out["QTdis"] = avg(qt_durs)
    out["QToffdis"] = avg(qt_durs)
    out["RSdis"] = avg(rs_durs)
    out["RTdis"] = avg(rs_durs) + avg(st_durs) * 0.5
    out["RToffdis"] = avg(rs_durs) + avg(st_durs)
    out["STdis"] = avg(st_durs)
    out["SToffdis"] = avg(st_durs)
    out["PonToffdis"] = out["PTseg"]

    # Slopes (mV/s or normalized)
    out["PQslope"] = avg(pq_slopes)
    out["QRslope"] = avg(qr_slopes)
    out["RSslope"] = avg(rs_slopes)
    out["STslope"] = avg(st_slopes)

    # Angles (degrees) from slope: angle = atan2(dy, dx), dx=1
    out["PonPQang"] = math.degrees(math.atan(avg(pq_slopes))) if pq_slopes else 0.0
    out["PQRang"] = out["PonPQang"]
    out["QRSang"] = math.degrees(math.atan(avg(qr_slopes))) if qr_slopes else 0.0
    out["RSTang"] = math.degrees(math.atan(avg(rs_slopes))) if rs_slopes else 0.0
    out["STToffang"] = math.degrees(math.atan(avg(st_slopes))) if st_slopes else 0.0

    # QRS area and perimeter
    out["QRSarea"] = avg(qrs_areas)
    out["QRSperi"] = avg(qrs_durs) * 2.0  # approximate perimeter in ms

    return out


def extract_ml_features(
    bpm: float,
    mean_rr_ms: Optional[float] = None,
    rr_std_ms: Optional[float] = None,
    rr_intervals_ms: Optional[List[float]] = None,
    num_beats: Optional[int] = None,
    duration_seconds: Optional[float] = None,
) -> Dict[str, float]:
    """
    Build the full ML feature dict from processed ECG / RR data.
    Fills RR and HRV features from rr_intervals; segment/angle features default to 0.
    """
    features = {name: 0.0 for name in ML_FEATURE_NAMES}

    features["hbpermin"] = bpm

    if mean_rr_ms is not None:
        features["RRmean"] = mean_rr_ms
        features["PPmean"] = mean_rr_ms
        features["IBIM"] = mean_rr_ms

    if rr_std_ms is not None:
        features["SDRR"] = rr_std_ms
        features["IBISD"] = rr_std_ms

    if rr_intervals_ms and len(rr_intervals_ms) >= 1:
        arr = np.array(rr_intervals_ms, dtype=float)
        features["RRTot"] = float(np.nansum(arr))
        features["NNTot"] = float(len(arr))
        features["RMSSD"] = _compute_rmssd(rr_intervals_ms)
        features["SDSD"] = _compute_sdsd(rr_intervals_ms)
        nn50, pnn50 = _compute_nn50_pnn50(rr_intervals_ms)
        features["NN50"] = float(nn50)
        features["pNN50"] = pnn50
        if features["RRmean"] == 0.0 and arr.size > 0:
            features["RRmean"] = _safe_mean(arr)
        if features["SDRR"] == 0.0 and arr.size >= 2:
            features["SDRR"] = _safe_std(arr)
    elif num_beats is not None and duration_seconds is not None and duration_seconds > 0:
        features["NNTot"] = float(num_beats - 1) if num_beats > 1 else 0.0
        if mean_rr_ms is not None and num_beats > 1:
            features["RRTot"] = mean_rr_ms * (num_beats - 1)

    return features
