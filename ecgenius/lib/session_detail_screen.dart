import 'package:flutter/material.dart';
import 'services/ecg_api_service.dart';

class SessionDetailScreen extends StatefulWidget {
  final ECGSession session;

  const SessionDetailScreen({required this.session, super.key});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final ECGApi _api = ECGApi();
  HealthStatus? healthStatus;
  Waveform? waveform;
  MlPrediction? mlPrediction;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    try {
      final results = await Future.wait([
        _api.getHealth(widget.session.id),
        _api.getWaveform(widget.session.id),
        _api.getMlPrediction(widget.session.id),
      ]);
      if (mounted) {
        setState(() {
          healthStatus = results[0] as HealthStatus;
          waveform = results[1] as Waveform;
          mlPrediction = results[2] as MlPrediction?;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      print('Error loading session data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E40AF),
          foregroundColor: Colors.white,
          title: const Text('Session Details'),
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final session = widget.session;
    final health = healthStatus;
    final wave = waveform;

    final date = session.startedAt;
    final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final duration = session.totalDurationSeconds != null
        ? '${session.totalDurationSeconds!.toStringAsFixed(1)}s'
        : 'Unknown';

    final bpm = health?.bpm.toInt() ?? 0;
    final status = health?.status ?? 'Unknown';
    final isElevated = status == 'tachycardia' || status == 'irregular_rhythm';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: const Text('Session Details'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Session Header Card
              Container(
                padding: const EdgeInsets.all(20),
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isElevated ? Colors.orange[100] : Colors.blue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.favorite,
                            color: isElevated ? Colors.orange[700] : Colors.blue[700],
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${bpm} BPM',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isElevated ? Colors.orange[100] : Colors.green[100],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: isElevated ? Colors.orange[900] : Colors.green[900],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem(
                            Icons.calendar_today,
                            'Date',
                            date.toLocal().toString().split(' ')[0],
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            Icons.access_time,
                            'Time',
                            time,
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            Icons.timer,
                            'Duration',
                            duration,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ECG Chart Section
              Container(
                padding: const EdgeInsets.all(20),
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
                    const Text(
                      'ECG Waveform',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (wave != null && wave.points.isNotEmpty)
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'ECG Waveform: ${wave.points.length} points',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.waves,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No waveform data available',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Analysis Section
              Container(
                padding: const EdgeInsets.all(20),
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
                    const Text(
                      'Session Analysis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (health != null) ...[
                      _buildAnalysisItem(
                        'Average BPM',
                        '${health.bpm.toInt()} bpm',
                        Icons.favorite,
                        Colors.red,
                      ),
                      const SizedBox(height: 12),
                      _buildAnalysisItem(
                        'Session Status',
                        health.status,
                        isElevated ? Icons.warning : Icons.check_circle,
                        isElevated ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(height: 12),
                      _buildAnalysisItem(
                        'Monitoring Duration',
                        '${health.durationSeconds.toStringAsFixed(1)}s',
                        Icons.timer,
                        Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      _buildAnalysisItem(
                        'Beats Detected',
                        '${health.numBeats}',
                        Icons.monitor_heart,
                        Colors.purple,
                      ),
                    ] else ...[
                      _buildAnalysisItem(
                        'Status',
                        'No health data available',
                        Icons.error,
                        Colors.grey,
                      ),
                    ],
                  ],
                ),
              ),

              if (mlPrediction != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
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
                        children: [
                          Icon(
                            Icons.psychology,
                            color: Colors.deepPurple[700],
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ML Classification',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildAnalysisItem(
                        'Prediction',
                        mlPrediction!.label,
                        Icons.flag,
                        _colorForMlClass(mlPrediction!.prediction),
                      ),
                      const SizedBox(height: 12),
                      _buildAnalysisItem(
                        'Confidence',
                        '${(mlPrediction!.confidence * 100).toStringAsFixed(1)}%',
                        Icons.verified,
                        Colors.deepPurple,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Implement export functionality
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Export functionality coming soon!'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Export Data'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF1E40AF)),
                        foregroundColor: const Color(0xFF1E40AF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to History'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E40AF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorForMlClass(String prediction) {
    switch (prediction) {
      case 'NSR':
        return Colors.green;
      case 'AFF':
      case 'ARR':
        return Colors.orange;
      case 'CHF':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E3A8A),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisItem(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E3A8A),
          ),
        ),
      ],
    );
  }
}
