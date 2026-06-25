import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/widgets/ecg_chart.dart';
import 'package:flutter/material.dart';

class SessionDetailsScreen extends StatefulWidget {
  final ECGSession session;

  const SessionDetailsScreen({required this.session, super.key});

  @override
  State<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends State<SessionDetailsScreen> {
  final ECGApi _api = ECGApi();
  List<double>? _waveformSamples;
  bool _isLoadingWaveform = true;
  String? _waveformError;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  Future<void> _loadWaveform() async {
    try {
      final waveform = await _api.getWaveform(widget.session.id);
      if (!mounted) return;
      setState(() {
        _waveformSamples = waveform.points.map((p) => p.value).toList();
        _isLoadingWaveform = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingWaveform = false;
        _waveformError = 'Could not load waveform: $e';
      });
    }
  }

  /// Parse "Age Range: X\nSymptoms: Y" from the raw symptoms string.
  Map<String, String> _parseSymptomsField(String? raw) {
    String ageRange = 'Not recorded';
    String symptoms = 'None recorded';

    if (raw == null || raw.trim().isEmpty) {
      return {'ageRange': ageRange, 'symptoms': symptoms};
    }

    final lines = raw.split('\n');
    for (final line in lines) {
      if (line.startsWith('Age Range:')) {
        final val = line.substring('Age Range:'.length).trim();
        if (val.isNotEmpty) ageRange = val;
      } else if (line.startsWith('Symptoms:')) {
        final val = line.substring('Symptoms:'.length).trim();
        if (val.isNotEmpty) symptoms = val;
      }
    }

    // Fallback: if the raw string doesn't follow the format, treat it all as symptoms
    if (ageRange == 'Not recorded' && symptoms == 'None recorded' && raw.trim().isNotEmpty) {
      symptoms = raw.trim();
    }

    return {'ageRange': ageRange, 'symptoms': symptoms};
  }

  Color _bpmColor(double? bpm) {
    if (bpm == null) return Colors.grey;
    if (bpm < 60) return Colors.blue[700]!;
    if (bpm > 100) return Colors.red[700]!;
    return Colors.green[700]!;
  }

  String _bpmLabel(double? bpm) {
    if (bpm == null) return 'Pending';
    if (bpm < 60) return 'Bradycardia';
    if (bpm > 100) return 'Tachycardia';
    return 'Normal';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final parsed = _parseSymptomsField(session.symptoms);
    final startedAt = session.startedAt.toLocal();
    final dateStr = '${startedAt.year}-${startedAt.month.toString().padLeft(2, '0')}-${startedAt.day.toString().padLeft(2, '0')}';
    final timeStr = '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: Text(session.name ?? 'Session ${session.id}'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ECG Waveform
              if (_isLoadingWaveform)
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  ),
                )
              else if (_waveformError != null)
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      _waveformError!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ECGChart(
                  monitoring: false,
                  samples: _waveformSamples ?? [],
                ),

              const SizedBox(height: 20),

              // BPM & Status Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _bpmColor(session.bpm).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.favorite, color: _bpmColor(session.bpm), size: 32),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.bpm != null ? '${session.bpm!.round()} BPM' : 'BPM Pending',
                            style: TextStyle(
                              color: _bpmColor(session.bpm),
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _bpmColor(session.bpm).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _bpmLabel(session.bpm),
                              style: TextStyle(
                                color: _bpmColor(session.bpm),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Patient Info Card (Age Range)
              _buildInfoCard(
                icon: Icons.person_outline,
                iconColor: Colors.indigo,
                title: 'Patient Age Range',
                value: parsed['ageRange']!,
              ),

              const SizedBox(height: 12),

              // Symptoms Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.medical_information_outlined, color: Colors.orange[700], size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Reported Symptoms',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      parsed['symptoms']!,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Session Metadata Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Session Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _metadataRow('Date', dateStr),
                    _metadataRow('Time', timeStr),
                    _metadataRow('Duration', session.totalDurationSeconds != null
                        ? '${session.totalDurationSeconds!.toStringAsFixed(0)} seconds'
                        : 'Unknown'),
                    _metadataRow('Sample Rate', '${session.samplingRateHz.toStringAsFixed(0)} Hz'),
                    _metadataRow('Source', session.source),
                    _metadataRow('Status', session.status),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}
