import 'dart:math' as math;

class EcgProcessedResult {
  final double bpm;
  final List<double> rrIntervalsMs;
  final List<int> rPeaksIndices;
  final List<double> rPeaksTimestampsMs;
  final String abnormality;
  final List<double> filteredSignal;
  final double samplingRateHz;
  final double durationSeconds;
  final int numBeats;
  final double? meanRrMs;
  final double? rrStdMs;

  EcgProcessedResult({
    required this.bpm,
    required this.rrIntervalsMs,
    required this.rPeaksIndices,
    required this.rPeaksTimestampsMs,
    required this.abnormality,
    required this.filteredSignal,
    required this.samplingRateHz,
    required this.durationSeconds,
    required this.numBeats,
    this.meanRrMs,
    this.rrStdMs,
  });
}

class Biquad {
  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad.lowpass(double fc, double fs) {
    final w0 = 2 * math.pi * fc / fs;
    final alpha = math.sin(w0) / math.sqrt(2);
    final c = math.cos(w0);
    final invA0 = 1.0 / (1.0 + alpha);
    return Biquad._(
      (1.0 - c) * 0.5 * invA0,
      (1.0 - c) * invA0,
      (1.0 - c) * 0.5 * invA0,
      -2.0 * c * invA0,
      (1.0 - alpha) * invA0,
    );
  }

  factory Biquad.highpass(double fc, double fs) {
    final w0 = 2 * math.pi * fc / fs;
    final alpha = math.sin(w0) / math.sqrt(2);
    final c = math.cos(w0);
    final invA0 = 1.0 / (1.0 + alpha);
    return Biquad._(
      (1.0 + c) * 0.5 * invA0,
      -(1.0 + c) * invA0,
      (1.0 + c) * 0.5 * invA0,
      -2.0 * c * invA0,
      (1.0 - alpha) * invA0,
    );
  }

  factory Biquad.notch(double f0, double fs, double q) {
    final w0 = 2 * math.pi * f0 / fs;
    final alpha = math.sin(w0) / (2 * q);
    final c = math.cos(w0);
    final invA0 = 1.0 / (1.0 + alpha);
    return Biquad._(
      1.0 * invA0,
      -2.0 * c * invA0,
      1.0 * invA0,
      -2.0 * c * invA0,
      (1.0 - alpha) * invA0,
    );
  }

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}

class CascadedFilter {
  final List<Biquad> sections;

  CascadedFilter._(this.sections);

  factory CascadedFilter.ecgFilter(double fs) {
    final order = [
      Biquad.highpass(0.5, fs),
      Biquad.highpass(0.5, fs),
      Biquad.notch(50, fs, 30),
      Biquad.lowpass(40, fs),
    ];
    return CascadedFilter._(order);
  }

  double process(double x) {
    var y = x;
    for (final s in sections) {
      y = s.process(y);
    }
    return y;
  }

  void reset() {
    for (final s in sections) {
      s.reset();
    }
  }
}

class EcgProcessor {
  final double samplingRate;
  CascadedFilter? _filter;
  int _sampleCount = 0;
  double _lastPeakVal = 0;
  int _lastPeakIdx = 0;
  double _signalMean = 0;
  double _signalMax = 0;
  double _threshold = 0;
  final List<int> _rPeaks = [];
  final List<double> _filteredBuf = [];

  EcgProcessor({this.samplingRate = 250.0});

  EcgProcessedResult process(List<double> raw,
      {double bandpassLow = 0.5,
      double bandpassHigh = 40.0,
      int bradyThresh = 60,
      int tachyThresh = 100}) {
    if (raw.length < samplingRate * 2) {
      throw Exception('ECG segment too short (min ~2 seconds)');
    }
    if (raw.any((v) => v.isNaN || v.isInfinite)) {
      throw Exception('ECG data contains NaN or Inf');
    }

    _filter = CascadedFilter.ecgFilter(samplingRate);
    _filteredBuf.clear();
    _rPeaks.clear();
    _sampleCount = 0;
    _lastPeakVal = 0;
    _lastPeakIdx = 0;
    _signalMean = 0;
    _signalMax = 0;

    for (final sample in raw) {
      final filtered = _filter!.process(sample);
      _filteredBuf.add(filtered);
      _sampleCount++;
    }

    _detectRPeaksOffline();
    final (rrMs, bpm, meanRr, rrStd) = _computeRrAndBpm(_rPeaks);
    final abn = _classifyAbnormality(bpm, rrStd, meanRr,
        bradyThresh: bradyThresh, tachyThresh: tachyThresh);
    final rTsMs = _rPeaks.map((i) => 1000.0 * i / samplingRate).toList();
    final durationS = raw.length / samplingRate;

    return EcgProcessedResult(
      bpm: bpm,
      rrIntervalsMs: rrMs,
      rPeaksIndices: List.from(_rPeaks),
      rPeaksTimestampsMs: rTsMs,
      abnormality: abn,
      filteredSignal: List.from(_filteredBuf),
      samplingRateHz: samplingRate,
      durationSeconds: durationS,
      numBeats: _rPeaks.length,
      meanRrMs: meanRr,
      rrStdMs: rrStd,
    );
  }

  double processSample(double rawSample) {
    _filter ??= CascadedFilter.ecgFilter(samplingRate);
    final filtered = _filter!.process(rawSample);
    _filteredBuf.add(filtered);
    _sampleCount++;
    return filtered;
  }

  List<int> getPeaks() {
    final minDist = (0.4 * samplingRate).round();
    final peaks = <int>[];
    var i = 0;
    while (i < _filteredBuf.length) {
      if (_filteredBuf[i] > _threshold) {
        var maxIdx = i;
        var maxVal = _filteredBuf[i];
        final end = (i + minDist).clamp(0, _filteredBuf.length);
        for (var j = i + 1; j < end; j++) {
          if (_filteredBuf[j] > maxVal) {
            maxVal = _filteredBuf[j];
            maxIdx = j;
          }
        }
        peaks.add(maxIdx);
        i = end;
      } else {
        i++;
      }
    }
    return peaks;
  }

  void _detectRPeaksOffline() {
    if (_filteredBuf.length < samplingRate) return;
    final buf = _filteredBuf;

    _signalMean = buf.reduce((a, b) => a + b) / buf.length;
    _signalMax = buf.reduce((a, b) => a > b ? a : b);

    _threshold = _signalMean + (_signalMax - _signalMean) * 0.4;

    final minDist = (0.4 * samplingRate).round();

    var i = 0;
    while (i < buf.length) {
      if (buf[i] > _threshold) {
        var maxIdx = i;
        var maxVal = buf[i];
        final end = (i + minDist).clamp(0, buf.length);
        for (var j = i + 1; j < end; j++) {
          if (buf[j] > maxVal) {
            maxVal = buf[j];
            maxIdx = j;
          }
        }
        _rPeaks.add(maxIdx);
        i = end;
      } else {
        i++;
      }
    }
  }

  (List<double>, double, double?, double?) _computeRrAndBpm(
      List<int> rPeaks) {
    if (rPeaks.length < 2) {
      return ([], 0.0, null, null);
    }
    final rrMs = <double>[];
    for (var i = 0; i < rPeaks.length - 1; i++) {
      rrMs.add(1000.0 * (rPeaks[i + 1] - rPeaks[i]) / samplingRate);
    }
    final meanRr = rrMs.reduce((a, b) => a + b) / rrMs.length;
    final variance =
        rrMs.map((v) => (v - meanRr) * (v - meanRr)).reduce((a, b) => a + b) /
            rrMs.length;
    final rrStd = math.sqrt(variance);
    final bpm = meanRr > 0 ? 60000.0 / meanRr : 0.0;
    return (rrMs, bpm, meanRr, rrStd);
  }

  String _classifyAbnormality(double bpm, double? rrStdMs, double? meanRrMs,
      {int bradyThresh = 60, int tachyThresh = 100}) {
    if (bpm <= 0) return 'normal';
    if (bpm < bradyThresh) return 'bradycardia';
    if (bpm > tachyThresh) return 'tachycardia';
    if (meanRrMs != null &&
        rrStdMs != null &&
        meanRrMs > 0 &&
        (rrStdMs / meanRrMs) > 0.25) {
      return 'irregular_rhythm';
    }
    return 'normal';
  }

  void reset() {
    _filter?.reset();
    _filter = null;
    _filteredBuf.clear();
    _rPeaks.clear();
    _sampleCount = 0;
    _lastPeakVal = 0;
    _lastPeakIdx = 0;
    _signalMean = 0;
    _signalMax = 0;
    _threshold = 0;
  }
}
