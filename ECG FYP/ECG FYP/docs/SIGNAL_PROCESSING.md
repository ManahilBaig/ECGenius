# ECG Signal Processing

This document explains **why** each step is used and **how** it matches **AD8232** output and typical ECG analysis.

---

## AD8232 and Input Assumptions

- **AD8232** outputs an **analog** ECG. The **ESP32** digitizes it with its **ADC** (e.g. 10–12 bit).
- **Sampling rate**: 250–360 Hz. We use **360 Hz** to align with **MIT-BIH** and our default.
- **Format**: stream of **numeric values** (ADC codes or scaled voltage). The processing is **scale-invariant** for R-peak and BPM.

---

## Processing Pipeline

```
Raw ECG (samples) → Baseline removal → Bandpass (0.5–40 Hz) → R-peak detection
                                                                      ↓
                                              BPM, RR intervals ←─────┘
                                              Abnormality (brady / tachy / irregular)
```

---

## 1. Baseline Wander Correction (High-Pass)

**What:** High-pass filter with cutoff ~**0.5 Hz** to remove very slow drift.

**Why:**

- **AD8232** picks up **respiration** and **body movement** (often 0.1–0.5 Hz).
- Electrode contact and skin impedance also drift slowly.
- The **QRS** and other waves of interest are above ~1 Hz. Removing &lt; 0.5 Hz keeps the waveform shape and improves R-peak detection.

**How (aligned with AD8232):**  
We use a **2nd-order high-pass** at 0.5 Hz. The same effect is also achieved by the bandpass (see below); we keep this step explicit in the code for clarity.

---

## 2. Bandpass Filter (0.5–40 Hz)

**What:** Bandpass **0.5–40 Hz** (2nd-order Butterworth).

**Why:**

| Band | Role |
|------|------|
| **&lt; 0.5 Hz** | Baseline wander, motion, respiration → **removed**. |
| **0.5–40 Hz** | P, QRS, T and most clinically useful content → **kept**. |
| **&gt; 40 Hz** | Muscle noise, 50/60 Hz mains, RF from Wi‑Fi/ESP32 → **removed**. |

**AD8232 relevance:**

- AD8232 has its own analog filtering; our bandpass defines the **digital** part of the pipeline.
- 40 Hz is a common upper limit for diagnostic ECG and avoids aliasing for 250–360 Hz sampling (Nyquist 125–180 Hz).

---

## 3. R-Peak Detection

**What:** Detector inspired by **Pan–Tompkins**:

1. **Derivative** of the filtered signal to emphasize the steep R-wave.
2. **Squaring** to stress large slopes.
3. **Moving integration** (window ~0.08 s) to smooth and form clear bumps at R-peaks.
4. **Peak search** with a minimum distance ~0.4 s (refractory period) and a prominence threshold.

**Why:**

- R-peaks are the most robust feature for **heart rate** and **RR intervals**.
- This works on **AD8232-like** signals: single-lead, 250–360 Hz, after bandpass.

---

## 4. BPM and RR Intervals

- **RR (ms)** = time between consecutive R-peaks:  
  `RR_ms = 1000 * (index_{i+1} - index_i) / sampling_rate`
- **BPM** = `60_000 / mean(RR_ms)`.

---

## 5. Abnormality Detection

| Condition | Rule |
|----------|------|
| **Bradycardia** | BPM &lt; 60 |
| **Tachycardia** | BPM &gt; 100 |
| **Irregular** | RR standard deviation &gt; 25% of mean RR (simple variability rule) |
| **Normal** | Otherwise |

Thresholds (60, 100) are configurable via `BRADYCARDIA_THRESHOLD` and `TACHYCARDIA_THRESHOLD`.

---

## 6. Corrupted and Invalid Data

Before processing, we check:

- Minimum length (~2 s at the given sampling rate).
- No **NaN** or **Inf**.
- No extreme values (e.g. &gt; 10⁶) that suggest ADC/sensor fault.

On failure, `process_ecg` raises **ValueError**; the API returns **400** with the error message.

---

## Summary Table

| Step | Purpose | AD8232 / ESP32 relevance |
|------|----------|----------------------------|
| Baseline / high-pass | Remove drift, motion, respiration | Matches typical single-lead and movement artifacts. |
| Bandpass 0.5–40 Hz | Keep diagnostic band, remove noise and mains | Fits 250–360 Hz sampling and common ECG practice. |
| R-peak detection | Find beats for BPM and RR | Works on single-lead, bandpass-filtered AD8232-like data. |
| BPM / RR | Heart rate and rhythm | Scale-invariant to ADC units. |
| Abnormality | Brady, tachy, irregular | Uses the same BPM and RR we already compute. |

---

## References (for reports / defense)

- **MIT-BIH Arrhythmia Database:** PhysioNet, 360 Hz, used to validate the pipeline before hardware.
- **Pan–Tompkins:** J. Pan, W.J. Tompkins, “A real-time QRS detection algorithm,” *IEEE Trans. Biomed. Eng.*, 1985.
- **AD8232:** Analog Devices datasheet for analog filtering and output characteristics.
