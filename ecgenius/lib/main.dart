import 'package:flutter/material.dart';
import 'package:ecgenius/ecg_screen.dart';

void main() {
  runApp(const ECGeniusApp());
}

class ECGeniusApp extends StatelessWidget {
  const ECGeniusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ECGScreen(),
    );
  }
}
