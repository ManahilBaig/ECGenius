import 'package:flutter/material.dart';
import 'dashboard_screen.dart';

void main() {
  runApp(const ECGeniusApp());
}

class ECGeniusApp extends StatelessWidget {
  const ECGeniusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DashboardScreen(),
    );
  }
}
