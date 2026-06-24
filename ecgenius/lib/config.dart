/// ECG App Configuration
/// Configure backend API endpoints and other settings here
library;

class AppConfig {
  // Backend API Configuration
  static const String backendHost = '127.0.0.1';
  static const int backendPort = 8001;
  static const String backendScheme = 'http';
  
  static String get backendUrl => '$backendScheme://$backendHost:$backendPort/api/v1';

  // Alternative configurations for different environments:
  // Production: 'http://your-server.com/api/v1'
  // Staging: 'http://staging.your-server.com/api/v1'
  // Local Docker: 'http://host.docker.internal:8000/api/v1'

  // App Settings
  static const String appName = 'ECGenius';
  static const String appVersion = '1.0.0';
  
  // Monitoring
  static const Duration bpmPollingInterval = Duration(seconds: 2);
  static const Duration waveformRefreshInterval = Duration(milliseconds: 50);
  
  // API Timeouts
  static const Duration apiTimeout = Duration(seconds: 10);
  static const Duration largeFileTimeout = Duration(seconds: 30);
  
  // BPM Thresholds
  static const int bradycardiaThreshold = 60;
  static const int tachycardiaThreshold = 100;
  
  // Sampling Rate
  static const double samplingRateHz = 360.0;
}
