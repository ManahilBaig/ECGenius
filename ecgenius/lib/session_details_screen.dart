import 'dart:io';
import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/widgets/ecg_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  MlPrediction? _mlPrediction;
  bool _isLoadingMl = true;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
    _loadMlPrediction();
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

  Future<void> _loadMlPrediction() async {
    try {
      final prediction = await _api.getMlPrediction(widget.session.id);
      if (!mounted) return;
      setState(() {
        _mlPrediction = prediction;
        _isLoadingMl = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMl = false);
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

  pw.Widget _buildEcgWaveformPdf(List<double> samples) {
    if (samples.isEmpty) {
      return pw.SizedBox(
        height: 120,
        child: pw.Center(child: pw.Text('No waveform data available')),
      );
    }

    const double chartWidth = 530;
    const double chartHeight = 160;
    const double pad = 10;
    const double drawW = chartWidth - 2 * pad;
    const double drawH = chartHeight - 2 * pad;

    const int sr = 360;
    const int fiveSeconds = sr * 5;
    final List<double> display = samples.length > fiveSeconds
        ? samples.sublist(0, fiveSeconds)
        : samples;

    final int n = display.length;
    final double minVal = display.reduce((a, b) => a < b ? a : b);
    final double maxVal = display.reduce((a, b) => a > b ? a : b);
    final double range = maxVal - minVal;
    final double scaleY = range > 0 ? drawH / range : 1.0;

    return pw.CustomPaint(
      size: const PdfPoint(chartWidth, chartHeight),
      painter: (PdfGraphics canvas, PdfPoint size) {
        canvas.setFillColor(PdfColor.fromHex('#FAFAFA'));
        canvas.drawRect(0, 0, size.x, size.y);
        canvas.fillPath();

        canvas.setStrokeColor(PdfColor.fromHex('#E0E0E0'));
        canvas.setLineWidth(0.3);
        for (double gy = pad; gy <= pad + drawH; gy += 20) {
          canvas.moveTo(pad, gy);
          canvas.lineTo(pad + drawW, gy);
        }
        for (double gx = pad; gx <= pad + drawW; gx += 40) {
          canvas.moveTo(gx, pad);
          canvas.lineTo(gx, pad + drawH);
        }
        canvas.strokePath();

        canvas.setStrokeColor(PdfColor.fromHex('#1B5E20'));
        canvas.setLineWidth(1.0);
        for (int i = 0; i < n; i++) {
          final double x = pad + (i / (n - 1)) * drawW;
          final double y = pad + drawH - ((display[i] - minVal) * scaleY);
          if (i == 0) {
            canvas.moveTo(x, y);
          } else {
            canvas.lineTo(x, y);
          }
        }
        canvas.strokePath();
      },
    );
  }

  String _symptomsForReport() {
    final pred = _mlPrediction?.prediction;
    if (pred == 'NSR') {
      return 'No symptoms detected';
    }
    final parsed = _parseSymptomsField(widget.session.symptoms);
    final userSymptoms = parsed['symptoms'] ?? 'None recorded';
    if (userSymptoms == 'None' || userSymptoms == 'None recorded') {
      return 'Possible arrhythmia detected — further clinical evaluation recommended.';
    }
    return userSymptoms;
  }

  Future<void> _exportPdf() async {
    final session = widget.session;
    final parsed = _parseSymptomsField(session.symptoms);
    final startedAt = session.startedAt.toLocal();

    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Header(level: 0, text: 'ECG Session Report', textStyle: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'Session Info'),
        pw.Text('Patient: ${session.name ?? 'N/A'}'),
        pw.Text('Date: ${startedAt.year}-${startedAt.month.toString().padLeft(2, '0')}-${startedAt.day.toString().padLeft(2, '0')}'),
        pw.Text('Time: ${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}'),
        pw.Text('Duration: ${session.totalDurationSeconds?.toStringAsFixed(0) ?? 'Unknown'} seconds'),
        pw.Text('Sample Rate: ${session.samplingRateHz.toStringAsFixed(0)} Hz'),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'Vitals'),
        pw.Text('BPM: ${session.bpm?.round().toString() ?? 'Pending'}'),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'ML Classification'),
        pw.Text('Result: ${_mlPrediction?.label ?? 'Not available'}'),
        pw.Text('Confidence: ${_mlPrediction != null ? '${(_mlPrediction!.confidence * 100).toStringAsFixed(1)}%' : 'N/A'}'),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'ECG Waveform (5 seconds)'),
        pw.SizedBox(height: 8),
        _buildEcgWaveformPdf(_waveformSamples ?? []),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'Patient Info'),
        pw.Text('Age Range: ${parsed['ageRange']}'),
        pw.SizedBox(height: 4),
        pw.Text('Symptoms:'),
        pw.Text(_symptomsForReport(), style: const pw.TextStyle(height: 1.5)),
        pw.SizedBox(height: 16),
        pw.Header(level: 1, text: 'Disclaimer'),
        pw.Text('This report is for informational purposes only and does not constitute a medical diagnosis. Consult a healthcare professional for interpretation.'),
      ],
    ));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ECG_Session_${session.id}.pdf');
    await file.writeAsBytes(await pdf.save());

    if (!mounted) return;
    await Share.shareXFiles([XFile(file.path)], text: 'ECG Session Report');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF saved: ${file.path}')),
    );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export as PDF',
            onPressed: _exportPdf,
          ),
        ],
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

              // ML Prediction Card
              if (_isLoadingMl)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_mlPrediction != null)
                _buildMlCard(_mlPrediction!),

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

  Widget _buildMlCard(MlPrediction ml) {
    final color = ml.prediction == 'NSR' ? Colors.green
        : (ml.prediction == 'AFF' || ml.prediction == 'ARR' || ml.prediction == 'CHF')
            ? Colors.amber[700]! : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(18),
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
              Icon(Icons.insights, color: color, size: 22),
              const SizedBox(width: 10),
              const Text('ML Classification',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ml.label,
                  style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${(ml.confidence * 100).toStringAsFixed(1)}% confidence',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          if (ml.probabilities != null) ...[
            const SizedBox(height: 12),
            ...ml.probabilities!.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: e.value, backgroundColor: Colors.grey[200], color: color, minHeight: 6),
                  )),
                  const SizedBox(width: 6),
                  SizedBox(width: 40, child: Text('${(e.value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11))),
                ],
              ),
            )),
          ],
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
