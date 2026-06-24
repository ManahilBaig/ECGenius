# Mock ECG Data

## Recommended: MIT-BIH Arrhythmia Database (PhysioNet)

- **Provider:** [PhysioNet](https://physionet.org/content/mitdb/1.0.0/)
- **Sampling rate:** 360 Hz (matches AD8232 target and our backend default)
- **Use:** Export as CSV (one column = ECG amplitude) and place here as `mit_bih_sample.csv` or any `*.csv`.

## Alternatives

- **PhysioNet Normal Sinus Rhythm DB:** [nsrdb](https://physionet.org/content/nsrdb/1.0.0/) — clean signals for baseline testing.
- **Kaggle ECG Heartbeat Categorization:** useful for classification logic; less focused on raw waveform.

## Format

- One numeric value per line (or one numeric column per row). Header lines starting with `#` are ignored.
- Units: arbitrary (we treat as ADC-like); scaling does not affect BPM or R-peak logic.

## Bundled Sample

`mit_bih_sample.csv` is a short synthetic excerpt for pipeline testing. Replace with real PhysioNet data for validation.
