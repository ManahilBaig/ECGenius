import 'package:ecgenius/patient_session_history_screen.dart';
import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:flutter/material.dart';

class SymptomEntryScreen extends StatefulWidget {
  final ECGSession session;
  final List<double> ecgSamples;
  final int finalBpm;
  final double totalDurationSeconds;

  const SymptomEntryScreen({
    required this.session,
    required this.ecgSamples,
    required this.finalBpm,
    required this.totalDurationSeconds,
    super.key,
  });

  @override
  State<SymptomEntryScreen> createState() => _SymptomEntryScreenState();
}

class _SymptomEntryScreenState extends State<SymptomEntryScreen> {
  final ECGApi _api = ECGApi();
  final TextEditingController _symptomsController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  Future<void> _endSession() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _api.completeSession(
        widget.session.id,
        samples: widget.ecgSamples,
        finalBpm: widget.finalBpm,
        totalDurationSeconds: widget.totalDurationSeconds,
        symptoms: _normalizedSymptoms,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => const PatientSessionHistoryScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save session: $e';
      });
    }
  }

  String? get _normalizedSymptoms {
    final text = _symptomsController.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: const Text('Symptom Entry Screen'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _symptomsController,
                        minLines: 6,
                        maxLines: 10,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          labelText: 'Symptoms (optional)',
                          hintText:
                              'Example: chest pain, dizziness, shortness of breath',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[800]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _endSession,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isSaving ? 'Saving Session...' : 'End Session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E40AF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
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
            'ECG recording complete',
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _summaryRow(Icons.favorite, 'BPM', '${widget.finalBpm}'),
          const SizedBox(height: 10),
          _summaryRow(Icons.timer, 'Duration',
              '${widget.totalDurationSeconds.toStringAsFixed(0)} seconds'),
          const SizedBox(height: 10),
          _summaryRow(
              Icons.show_chart, 'ECG samples', '${widget.ecgSamples.length}'),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1E40AF), size: 20),
        const SizedBox(width: 10),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ],
    );
  }
}
