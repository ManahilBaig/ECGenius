import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class ECGSession {
  final int id;
  final String? name;
  final double samplingRateHz;
  final String source;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? totalDurationSeconds;
  final double? bpm;
  final String? symptoms;

  ECGSession({
    required this.id,
    this.name,
    required this.samplingRateHz,
    required this.source,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.totalDurationSeconds,
    this.bpm,
    this.symptoms,
  });

  factory ECGSession.fromJson(Map<String, dynamic> json) {
    return ECGSession(
      id: json['id'] as int,
      name: json['name'] as String?,
      samplingRateHz: (json['sampling_rate_hz'] as num).toDouble(),
      source: json['source'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      totalDurationSeconds:
          (json['total_duration_seconds'] as num?)?.toDouble(),
      bpm: (json['bpm'] as num?)?.toDouble(),
      symptoms: json['symptoms'] as String?,
    );
  }
}

class HealthStatus {
  final double bpm;
  final String status;
  final int numBeats;
  final double durationSeconds;
  final double? meanRrMs;

  HealthStatus({
    required this.bpm,
    required this.status,
    required this.numBeats,
    required this.durationSeconds,
    this.meanRrMs,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      bpm: (json['bpm'] as num).toDouble(),
      status: json['status'] as String,
      numBeats: json['num_beats'] as int,
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      meanRrMs: (json['mean_rr_ms'] as num?)?.toDouble(),
    );
  }
}

class WaveformPoint {
  final double tMs;
  final double value;

  WaveformPoint({required this.tMs, required this.value});

  factory WaveformPoint.fromJson(Map<String, dynamic> json) {
    return WaveformPoint(
      tMs: (json['t_ms'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
    );
  }
}

class Waveform {
  final int sessionId;
  final double samplingRateHz;
  final List<WaveformPoint> points;
  final bool isFiltered;

  Waveform({
    required this.sessionId,
    required this.samplingRateHz,
    required this.points,
    required this.isFiltered,
  });

  factory Waveform.fromJson(Map<String, dynamic> json) {
    final pointsList = (json['points'] as List)
        .map((p) => WaveformPoint.fromJson(p as Map<String, dynamic>))
        .toList();

    return Waveform(
      sessionId: json['session_id'] as int,
      samplingRateHz: (json['sampling_rate_hz'] as num).toDouble(),
      points: pointsList,
      isFiltered: json['is_filtered'] as bool? ?? true,
    );
  }
}

class Alert {
  final int id;
  final int sessionId;
  final String alertType;
  final String severity;
  final String? message;

  Alert({
    required this.id,
    required this.sessionId,
    required this.alertType,
    required this.severity,
    this.message,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      alertType: json['alert_type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String?,
    );
  }
}

class MlPrediction {
  final String prediction;
  final double confidence;
  final Map<String, double>? probabilities;

  MlPrediction({
    required this.prediction,
    required this.confidence,
    this.probabilities,
  });

  String get label {
    switch (prediction) {
      case 'AFF':
        return 'Atrial Fibrillation/Flutter';
      case 'ARR':
        return 'Other Arrhythmia';
      case 'CHF':
        return 'Congestive Heart Failure';
      case 'NSR':
        return 'Normal Sinus Rhythm';
      default:
        return prediction;
    }
  }
}

class ECGApiException implements Exception {
  final String message;
  final int? statusCode;

  ECGApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ECGApiException: $message (Status: $statusCode)';
}

class ECGApi {
  final String baseUrl;
  final http.Client httpClient;

  ECGApi({
    String? baseUrl,
    http.Client? httpClient,
  })  : baseUrl = baseUrl ?? AppConfig.backendUrl,
        httpClient = httpClient ?? http.Client();

  Future<ECGSession> createSession({
    String? name,
    double samplingRateHz = AppConfig.samplingRateHz,
    String source = 'app',
  }) async {
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl/ecg/sessions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'sampling_rate_hz': samplingRateHz,
            'source': source,
          }),
        )
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to create session');
    return ECGSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ECGSession> completeSession(
    int sessionId, {
    required List<double> samples,
    required int finalBpm,
    required double totalDurationSeconds,
    String? symptoms,
  }) async {
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl/ecg/sessions/$sessionId/complete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'samples': samples,
            'final_bpm': finalBpm,
            'total_duration_seconds': totalDurationSeconds,
            'symptoms': symptoms,
          }),
        )
        .timeout(AppConfig.largeFileTimeout);

    _throwIfFailed(response, 'Failed to complete session');
    return ECGSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ECGSession>> listSessions({int skip = 0}) async {
    final response = await httpClient
        .get(Uri.parse('$baseUrl/ecg/sessions?skip=$skip'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to list sessions');
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((s) => ECGSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<ECGSession> getSession(int sessionId) async {
    final response = await httpClient
        .get(Uri.parse('$baseUrl/ecg/sessions/$sessionId'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to get session');
    return ECGSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<HealthStatus> getHealth(int sessionId) async {
    final response = await httpClient
        .get(Uri.parse('$baseUrl/ecg/sessions/$sessionId/health'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to get health status');
    return HealthStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Waveform> getWaveform(int sessionId, {bool filtered = true}) async {
    final response = await httpClient
        .get(Uri.parse(
            '$baseUrl/ecg/sessions/$sessionId/waveform?filtered=$filtered'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to get waveform');
    return Waveform.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Alert>> listAlerts({int? sessionId, int skip = 0}) async {
    final queryParams = <String, String>{'skip': skip.toString()};
    if (sessionId != null) {
      queryParams['session_id'] = sessionId.toString();
    }

    final uri =
        Uri.parse('$baseUrl/ecg/alerts').replace(queryParameters: queryParams);
    final response = await httpClient.get(uri).timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to list alerts');
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((a) => Alert.fromJson(a as Map<String, dynamic>)).toList();
  }

  Future<MlPrediction?> getMlPrediction(int sessionId) async {
    final response = await httpClient
        .get(Uri.parse('$baseUrl/ecg/sessions/$sessionId/ml-prediction'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to get ML prediction');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prediction = data['prediction'] as String?;
    if (prediction == null) {
      return null;
    }

    return MlPrediction(
      prediction: prediction,
      confidence: (data['confidence'] as num? ?? 0).toDouble(),
      probabilities: (data['probabilities'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
    );
  }

  Future<void> deleteSession(int sessionId) async {
    final response = await httpClient
        .delete(Uri.parse('$baseUrl/ecg/sessions/$sessionId'))
        .timeout(AppConfig.apiTimeout);

    _throwIfFailed(response, 'Failed to delete session');
  }

  void _throwIfFailed(http.Response response, String message) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ECGApiException(
      '$message: ${response.body}',
      statusCode: response.statusCode,
    );
  }
}
