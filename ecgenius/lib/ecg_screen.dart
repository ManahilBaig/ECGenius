import 'dart:async';
import 'dart:math' show pi, sin;

import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/symptom_entry_screen.dart';
import 'package:ecgenius/widgets/ecg_chart.dart';
import 'package:flutter/material.dart';

class ECGScreen extends StatefulWidget {
  final bool autoStart;

  const ECGScreen({this.autoStart = true, super.key});

  @override
  State<ECGScreen> createState() => _ECGScreenState();
}

class _ECGScreenState extends State<ECGScreen> {
  static const Duration recordingDuration = Duration(seconds: 15);
  static const double samplingRateHz = 360;
  static const Duration tickInterval = Duration(milliseconds: 50);

  final ECGApi _api = ECGApi();
  final List<double> _samples = [];
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _recordingTimer;
  ECGSession? _session;
  bool _isStarting = false;
  bool _isRecording = false;
  String? _errorMessage;
  int _bpm = 72;
  int _secondsRemaining = recordingDuration.inSeconds;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      unawaited(_startRecording());
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _samples.clear();
      _secondsRemaining = recordingDuration.inSeconds;
      _bpm = 72;
    });

    try {
      final session = await _api.createSession(
        name: 'ECG Session ${DateTime.now().toLocal()}',
        samplingRateHz: samplingRateHz,
        source: 'app',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
        _isStarting = false;
        _isRecording = true;
      });
      _stopwatch
        ..reset()
        ..start();
      _recordingTimer = Timer.periodic(tickInterval, (_) => _recordTick());
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStarting = false;
        _isRecording = false;
        _errorMessage = 'Unable to start ECG session: $e';
      });
    }
  }

  void _recordTick() {
    final elapsed = _stopwatch.elapsed;
    final remaining = recordingDuration - elapsed;
    final nextRemaining = remaining.isNegative ? 0 : remaining.inSeconds + 1;

    final samplesPerTick =
        (samplingRateHz * tickInterval.inMilliseconds / 1000).round();
    for (var i = 0; i < samplesPerTick; i++) {
      final sampleIndex = _samples.length;
      _samples.add(_generateEcgSample(sampleIndex, _bpm));
    }

    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final nextBpm = 72 + (4 * sin(elapsedSeconds * 0.9)).round();

    if (!mounted) {
      return;
    }
    setState(() {
      _bpm = nextBpm;
      _secondsRemaining =
          nextRemaining.clamp(0, recordingDuration.inSeconds).toInt();
    });

    if (elapsed >= recordingDuration) {
      _finishRecording();
    }
  }

  double _generateEcgSample(int sampleIndex, int bpm) {
    final seconds = sampleIndex / samplingRateHz;
    final beatLength = 60 / bpm;
    final phase = (seconds % beatLength) / beatLength;
    final baseline = 0.03 * sin(2 * pi * seconds * 0.4);

    if (phase < 0.08) {
      return baseline + 0.18 * sin(pi * phase / 0.08);
    }
    if (phase < 0.12) {
      return baseline - 0.35 * sin(pi * (phase - 0.08) / 0.04);
    }
    if (phase < 0.18) {
      return baseline + 1.35 * sin(pi * (phase - 0.12) / 0.06);
    }
    if (phase < 0.24) {
      return baseline - 0.28 * sin(pi * (phase - 0.18) / 0.06);
    }
    if (phase < 0.46) {
      return baseline + 0.32 * sin(pi * (phase - 0.24) / 0.22);
    }
    return baseline;
  }

  void _finishRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _stopwatch.stop();
    if (!mounted || _session == null) {
      return;
    }
    setState(() {
      _isRecording = false;
      _secondsRemaining = 0;
    });
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SymptomEntryScreen(
          session: _session!,
          ecgSamples: List<double>.unmodifiable(_samples),
          finalBpm: _bpm,
          totalDurationSeconds: recordingDuration.inSeconds.toDouble(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elapsedSeconds = recordingDuration.inSeconds - _secondsRemaining;
    final progress =
        (elapsedSeconds / recordingDuration.inSeconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: const Text('ECG Screen'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(progress),
              const SizedBox(height: 20),
              ECGChart(monitoring: _isRecording, samples: _samples),
              const SizedBox(height: 20),
              _buildBpmCard(),
              const SizedBox(height: 20),
              if (_errorMessage != null) _buildErrorCard(),
              if (_isStarting) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
              Text(
                _isRecording
                    ? 'Recording will stop automatically after 15 seconds.'
                    : 'Preparing the next step...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(double progress) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isRecording ? 'Recording ECG' : 'Starting ECG',
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$_secondsRemaining s left',
                style: const TextStyle(
                  color: Color(0xFF1E40AF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.blue[50],
            color: const Color(0xFF1E40AF),
            borderRadius: BorderRadius.circular(99),
          ),
        ],
      ),
    );
  }

  Widget _buildBpmCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.favorite, color: Colors.red[600], size: 30),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live BPM',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Text(
                '$_bpm',
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_errorMessage!, style: TextStyle(color: Colors.red[900])),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isStarting ? null : _startRecording,
            child: const Text('Retry ECG Session'),
          ),
        ],
      ),
    );
  }
}
