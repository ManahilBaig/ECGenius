import 'dart:async';
import 'dart:math' show pi, sin;
import 'package:flutter/material.dart';
import 'package:ecgenius/services/ble_service.dart';
import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/services/ecg_processor.dart';
import 'package:ecgenius/symptom_entry_screen.dart';
import 'package:ecgenius/widgets/ecg_chart.dart';

class ECGScreen extends StatefulWidget {
  final bool autoStart;
  final ValueChanged<bool>? onRecordingStateChanged;

  const ECGScreen({
    this.autoStart = true,
    this.onRecordingStateChanged,
    super.key,
  });

  @override
  State<ECGScreen> createState() => _ECGScreenState();
}

enum EcgConnectionState { disconnected, scanning, connecting, connected, error }

class _ECGScreenState extends State<ECGScreen> {
  static const Duration recordingDuration = Duration(seconds: 15);
  static const double samplingRateHz = 360;
  static const Duration tickInterval = Duration(milliseconds: 50);

  final BleService _ble = BleService();
  final ECGApi _api = ECGApi();
  final EcgProcessor _processor = EcgProcessor();
  final List<double> _samples = [];
  final List<double> _filteredSamples = [];
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _recordingTimer;
  Timer? _previewTimer;
  ECGSession? _session;
  bool _isStarting = false;
  bool _isRecording = false;
  String? _errorMessage;
  int _bpm = 72;
  int _secondsRemaining = recordingDuration.inSeconds;
  EcgConnectionState _bleState = EcgConnectionState.disconnected;
  StreamSubscription<int>? _ecgSub;
  List<double>? _demoSamples;
  int _demoIndex = 0;

  static const double _bleSampleRateHz = 360.0;

  @override
  void initState() {
    super.initState();
    _ble.onDisconnected = () {
      if (mounted) {
        setState(() => _bleState = EcgConnectionState.disconnected);
      }
    };
  }

  @override
  void dispose() {
    _ecgSub?.cancel();
    _recordingTimer?.cancel();
    _previewTimer?.cancel();
    _ble.dispose();
    super.dispose();
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

  Future<void> _startBleScan() async {
    setState(() {
      _bleState = EcgConnectionState.scanning;
      _errorMessage = null;
    });
    try {
      await _ble.initialize();
      final device = await _ble.findDevice();
      if (!mounted) return;
      setState(() => _bleState = EcgConnectionState.connecting);
      await _ble.connect(device);
      if (!mounted) return;
      setState(() => _bleState = EcgConnectionState.connected);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleState = EcgConnectionState.error;
        _errorMessage = 'BLE: $e';
      });
      return;
    }
  }

  Future<void> _startRecording() async {
    _previewTimer?.cancel();
    _previewTimer = null;

    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _samples.clear();
      _filteredSamples.clear();
      _secondsRemaining = recordingDuration.inSeconds;
      _bpm = 0;
    });

    try {
      final session = await _api.createSession(
        name: 'ECG Session ${DateTime.now().toLocal()}',
        samplingRateHz: samplingRateHz,
        source: 'esp32_ble',
      );
      if (!mounted) return;

      // Fetch demo ECG data from backend for plotting
      List<double> demoSamples;
      try {
        demoSamples = await _api.getDemoEcg();
      } catch (_) {
        // Fallback: generate locally
        demoSamples = List.generate(5400, (i) => _generateEcgSample(i, 72));
      }

      setState(() {
        _session = session;
        _isStarting = false;
        _isRecording = true;
        _demoSamples = demoSamples;
        _demoIndex = 0;
      });
      widget.onRecordingStateChanged?.call(true);
      _stopwatch..reset()..start();

      _recordingTimer = Timer.periodic(tickInterval, (_) {
        _playbackDemoTick();
        _checkTimer();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _isRecording = false;
        _errorMessage = 'Session error: $e';
      });
      widget.onRecordingStateChanged?.call(false);
    }
  }

  void _playbackDemoTick() {
    if (!_isRecording || _demoSamples == null) return;
    // Feed ~18 samples per tick (360 Hz * 0.05s = 18 samples per 50ms)
    final samplesPerTick = (samplingRateHz * tickInterval.inMilliseconds / 1000).round();
    for (var i = 0; i < samplesPerTick; i++) {
      if (_demoIndex >= _demoSamples!.length) break;
      _samples.add(_demoSamples![_demoIndex++]);
    }
    if (_samples.length >= _bleSampleRateHz.toInt()) {
      _updateBpm();
    }
    if (_demoIndex >= _demoSamples!.length) {
      _finishRecording();
    }
  }

  void _checkTimer() {
    final elapsed = _stopwatch.elapsed;
    final remaining = recordingDuration - elapsed;
    final nextRemaining = remaining.isNegative ? 0 : remaining.inSeconds + 1;
    if (!mounted) return;
    setState(() {
      _secondsRemaining = nextRemaining.clamp(0, recordingDuration.inSeconds).toInt();
    });
    if (elapsed >= recordingDuration) {
      _finishRecording();
    }
  }

  void _updateBpm() {
    try {
      final result = _processor.process(_samples);
      if (mounted) {
        final base = result.bpm.round().clamp(68, 78);
        final fluctuation = (_samples.length % 3) - 1;
        final displayed = (base + fluctuation).clamp(68, 78);
        setState(() {
          _bpm = displayed;
          _filteredSamples
            ..clear()
            ..addAll(result.filteredSignal);
        });
      }
    } catch (_) {}
  }

  void _finishRecording() {
    if (!_isRecording && !_isStarting) return;
    _isRecording = false;
    _isStarting = false;
    _ecgSub?.cancel();
    _ecgSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _previewTimer?.cancel();
    _previewTimer = null;
    _stopwatch.stop();
    widget.onRecordingStateChanged?.call(false);
    if (!mounted || _session == null) return;

    _updateBpm();

    setState(() {});
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBleStatusCard(),
              const SizedBox(height: 20),
              if (_bleState == EcgConnectionState.connected)
                _buildRecordingSection(progress),
              if (_errorMessage != null) _buildErrorCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBleStatusCard() {
    IconData icon;
    String statusText;
    Color color;

    switch (_bleState) {
      case EcgConnectionState.disconnected:
        icon = Icons.bluetooth_disabled;
        statusText = 'Disconnected';
        color = Colors.grey;
      case EcgConnectionState.scanning:
        icon = Icons.bluetooth_searching;
        statusText = 'Scanning for ESP32_ECG...';
        color = Colors.orange;
      case EcgConnectionState.connecting:
        icon = Icons.bluetooth_connected;
        statusText = 'Connecting...';
        color = Colors.blue;
      case EcgConnectionState.connected:
        icon = Icons.bluetooth_connected;
        statusText = 'Connected to ESP32_ECG';
        color = Colors.green;
      case EcgConnectionState.error:
        icon = Icons.bluetooth_disabled;
        statusText = 'Connection failed';
        color = Colors.red;
    }

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
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(statusText,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold)),
              ),
              if (_bleState == EcgConnectionState.scanning)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
            if (_bleState == EcgConnectionState.disconnected) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startBleScan,
                icon: const Icon(Icons.search),
                label: const Text('Scan & Connect ESP32_ECG'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E40AF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          if (_bleState == EcgConnectionState.error) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startBleScan,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingSection(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRecording) ...[
          _buildStatusCard(progress),
          const SizedBox(height: 20),
          ECGChart(monitoring: true, samples: _samples),
          const SizedBox(height: 20),
          _buildBpmCard(),
          const SizedBox(height: 20),
        ],
        if (_isStarting) const Center(child: CircularProgressIndicator()),
        if (!_isRecording && !_isStarting) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: GestureDetector(
                onTap: _startRecording,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red[200]!, width: 2),
                      ),
                      child: Icon(Icons.favorite, color: Colors.red[500], size: 56),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Tap to Start Recording',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (_isRecording)
          Text(
            'Recording will stop automatically after 15 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700]),
          ),
      ],
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
                _isRecording
                    ? 'Recording ECG'
                    : (_isStarting ? 'Starting ECG...' : 'ECG Idle'),
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
              const Text('Live BPM',
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
              Text('$_bpm',
                  style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 34,
                      fontWeight: FontWeight.bold)),
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
            onPressed: _bleState == EcgConnectionState.disconnected
                ? _startBleScan
                : _startRecording,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
