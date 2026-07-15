import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedBackendHost =
      String.fromEnvironment('ECG_BACKEND_HOST');
  static const int backendPort = 8000;
  static const String backendScheme = 'http';

  static String get backendHost {
    if (_definedBackendHost.isNotEmpty) {
      return _definedBackendHost;
    }
    return kIsWeb ? '127.0.0.1' : '10.0.2.2';
  }

  static String get backendUrl =>
      '$backendScheme://$backendHost:$backendPort/api/v1';

  static const String appName = 'ECGenius';
  static const String appVersion = '1.0.0';

  static const Duration bpmPollingInterval = Duration(seconds: 2);
  static const Duration waveformRefreshInterval = Duration(milliseconds: 50);

  static const Duration apiTimeout = Duration(seconds: 10);
  static const Duration largeFileTimeout = Duration(seconds: 30);

  static const int bradycardiaThreshold = 60;
  static const int tachycardiaThreshold = 100;

  static const double samplingRateHz = 360.0;
}
