import 'package:ecgenius/main_tab_controller.dart';
import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? _selectedAgeRange;
  bool _isSaving = false;
  String? _errorMessage;
  MlPrediction? _mlPrediction;
  bool _isLoadingPrediction = false;

  @override
  void dispose() {
    _symptomsController.dispose();
    super.dispose();
  }

  String? _patientName;
  bool _isDoctor = false;

  @override
  void initState() {
    super.initState();
    _checkDoctorAccount();
  }

  Future<void> _checkDoctorAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email') ?? '';
    if (!mounted) return;
    setState(() {
      _isDoctor = email == 'doctor@ecgenius.com';
    });
  }

  Future<void> _endSession() async {
    if (_selectedAgeRange == null) {
      setState(() {
        _errorMessage = 'Please select your age range';
      });
      return;
    }

    if (widget.ecgSamples.isEmpty) {
      await _api.deleteSession(widget.session.id);
      if (!mounted) return;
      _showRetryDialog('No ECG data was recorded. Please try again.');
      return;
    }

    if (_isDoctor && (_patientName == null || _patientName!.trim().isEmpty)) {
      final name = await _showPatientNameDialog();
      if (name == null || name.trim().isEmpty) return;
      setState(() => _patientName = name.trim());
    } else if (!_isDoctor) {
      final prefs = await SharedPreferences.getInstance();
      final fullName = prefs.getString('user_name') ?? '';
      if (fullName.isNotEmpty) {
        _patientName = fullName;
      }
    }

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
        symptoms: _normalizedSymptoms(),
        name: _patientName,
      );
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _isLoadingPrediction = true;
      });

      final prediction =
          await _api.getMlPrediction(widget.session.id);
      if (!mounted) return;

      setState(() {
        _mlPrediction = prediction;
        _isLoadingPrediction = false;
      });
    } catch (e) {
      if (!mounted) return;
      await _api.deleteSession(widget.session.id);
      if (!mounted) return;
      _showRetryDialog('Unable to save session. Please try again.');
    }
  }

  Future<String?> _showPatientNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Patient Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Patient name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showRetryDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Recording Failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => const MainTabController(initialIndex: 0)),
                (route) => false,
              );
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _goToHistory() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) => const MainTabController(initialIndex: 1)),
      (route) => false,
    );
  }

  String _normalizedSymptoms() {
    final ageStr = _selectedAgeRange ?? 'Not specified';
    final symptomsStr = _symptomsController.text.trim();
    if (symptomsStr.isEmpty) return 'Age Range: $ageStr\nSymptoms: None';
    return 'Age Range: $ageStr\nSymptoms: $symptomsStr';
  }

  Color _predictionColor(String? prediction) {
    if (prediction == null) return Colors.grey;
    if (prediction == 'NSR') return Colors.green;
    if (prediction == 'AFF' || prediction == 'ARR' || prediction == 'CHF') {
      return Colors.amber[700]!;
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        title: Text(_mlPrediction != null ? 'Session Complete' : 'Symptom Entry'),
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
                      if (_mlPrediction != null) ...[
                        const SizedBox(height: 20),
                        _buildPredictionCard(),
                      ],
                      if (_isLoadingPrediction) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('Running ML analysis...'),
                            ],
                          ),
                        ),
                      ],
                      if (_mlPrediction == null && !_isLoadingPrediction) ...[
                        const SizedBox(height: 24),
                        _buildSymptomsForm(),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                              color: Colors.red[800],
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_mlPrediction != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _goToHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('View Session History'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              if (_mlPrediction == null && !_isLoadingPrediction) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _endSession,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                        _isSaving ? 'Saving Session...' : 'End Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
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
          _summaryRow(Icons.show_chart, 'ECG samples',
              '${widget.ecgSamples.length}'),
        ],
      ),
    );
  }

  Widget _buildPredictionCard() {
    final color = _predictionColor(_mlPrediction?.prediction);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, color: color, size: 28),
              const SizedBox(width: 12),
              const Text('ML Classification',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text(_mlPrediction?.label ?? 'Unknown',
              style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          if (_mlPrediction?.probabilities != null) ...[
            const SizedBox(height: 16),
            ...(_mlPrediction!.probabilities!.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 40,
                        child: Text(e.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: e.value,
                          backgroundColor: Colors.grey[200],
                          color: color,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                          '${(e.value * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            })),
          ],
        ],
      ),
    );
  }

  Widget _buildSymptomsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedAgeRange,
          decoration: InputDecoration(
            labelText: 'Age Range (required)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            prefixIcon: const Icon(Icons.person_outline),
          ),
          items: const [
            DropdownMenuItem(
                value: 'Under 18', child: Text('Under 18')),
            DropdownMenuItem(value: '18-29', child: Text('18-29')),
            DropdownMenuItem(value: '30-44', child: Text('30-44')),
            DropdownMenuItem(value: '45-59', child: Text('45-59')),
            DropdownMenuItem(value: '60-74', child: Text('60-74')),
            DropdownMenuItem(value: '75+', child: Text('75+')),
          ],
          onChanged: (value) {
            setState(() => _selectedAgeRange = value);
          },
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _symptomsController,
          minLines: 6,
          maxLines: 10,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: 'Symptoms (optional)',
            hintText: 'Example: chest pain, dizziness, shortness of breath',
            alignLabelWithHint: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1E40AF), size: 20),
        const SizedBox(width: 10),
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ],
    );
  }

}
