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

  ECGSession({
    required this.id,
    this.name,
    required this.samplingRateHz,
    required this.source,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.totalDurationSeconds,
  });

  factory ECGSession.fromJson(Map<String, dynamic> json) {
    return ECGSession(
      id: json['id'] as int,
      name: json['name'] as String?,
      samplingRateHz: (json['sampling_rate_hz'] as num).toDouble(),
      source: json['source'] as String,
      status: json['status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
      totalDurationSeconds: (json['total_duration_seconds'] as num?)?.toDouble(),
    );
  }
}

class HealthStatus {
  final double bpm;
  final String status; // normal, bradycardia, tachycardia, irregular_rhythm
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
  final String severity; // high, medium, low
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

/// ML model classification result (AFF, ARR, CHF, NSR).
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
    double samplingRateHz = 360.0,
    String source = 'mock',
  }) async {
    try {
      final response = await httpClient.post(
        Uri.parse('$baseUrl/ecg/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'sampling_rate_hz': samplingRateHz,
          'source': source,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to create session: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return ECGSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      throw ECGApiException('Error creating session: $e');
    }
  }

  Future<List<ECGSession>> listSessions({int skip = 0, int limit = 50}) async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/sessions?skip=$skip&limit=$limit'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to list sessions: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((s) => ECGSession.fromJson(s as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ECGApiException('Error listing sessions: $e');
    }
  }

  Future<ECGSession> getSession(int sessionId) async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/sessions/$sessionId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to get session: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return ECGSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      throw ECGApiException('Error getting session: $e');
    }
  }

  Future<Map<String, dynamic>> uploadBulk(
    List<double> samples, {
    double samplingRateHz = 360.0,
    String? sessionName,
    int? userId,
  }) async {
    try {
      final response = await httpClient.post(
        Uri.parse('$baseUrl/ecg/upload-bulk'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'samples': samples,
          'sampling_rate_hz': samplingRateHz,
          'session_name': sessionName,
          'user_id': userId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to upload ECG data: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ECGApiException('Error uploading ECG data: $e');
    }
  }

  Future<HealthStatus> getHealth(int sessionId) async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/sessions/$sessionId/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to get health status: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return HealthStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      throw ECGApiException('Error getting health status: $e');
    }
  }

  Future<Waveform> getWaveform(
    int sessionId, {
    bool filtered = true,
  }) async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/sessions/$sessionId/waveform?filtered=$filtered'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to get waveform: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return Waveform.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      throw ECGApiException('Error getting waveform: $e');
    }
  }

  Future<List<Alert>> getAlerts({
    int? sessionId,
    int skip = 0,
    int limit = 50,
  }) async {
    try {
      String query = '?skip=$skip&limit=$limit';
      if (sessionId != null) {
        query += '&session_id=$sessionId';
      }

      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/alerts$query'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to get alerts: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((a) => Alert.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ECGApiException('Error getting alerts: $e');
    }
  }

  /// ML classification for a session (AFF, ARR, CHF, NSR). Returns null if unavailable.
  Future<MlPrediction?> getMlPrediction(int sessionId) async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/sessions/$sessionId/ml-prediction'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final prediction = map['prediction'] as String?;
      if (prediction == null ||
          map['error'] != null ||
          prediction == 'unknown' ||
          prediction == 'error') {
        return null;
      }
      return MlPrediction(
        prediction: prediction,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
        probabilities: map['probabilities'] != null
            ? Map<String, double>.from(
                (map['probabilities'] as Map).map(
                  (k, v) => MapEntry(k as String, (v as num).toDouble()),
                ),
              )
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getMockSample() async {
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/ecg/mock/sample'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to get mock sample: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ECGApiException('Error getting mock sample: $e');
    }
  }

  Future<void> deleteSession(int sessionId) async {
    try {
      final response = await httpClient.delete(
        Uri.parse('$baseUrl/ecg/sessions/$sessionId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw ECGApiException(
          'Failed to delete session: ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      throw ECGApiException('Error deleting session: $e');
    }
  }
}
