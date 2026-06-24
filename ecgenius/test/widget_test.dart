import 'package:ecgenius/ecg_screen.dart';
import 'package:ecgenius/patient_session_history_screen.dart';
import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/symptom_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ECG screen shows live BPM and countdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ECGScreen(autoStart: false)),
    );

    expect(find.text('ECG Screen'), findsOneWidget);
    expect(find.text('Live BPM'), findsOneWidget);
    expect(find.text('15 s left'), findsOneWidget);
    expect(find.text('End Session'), findsNothing);
  });

  testWidgets('Symptom screen owns End Session action', (tester) async {
    final session = ECGSession(
      id: 1,
      name: 'Test ECG Session',
      samplingRateHz: 360,
      source: 'app',
      status: 'recording',
      startedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SymptomEntryScreen(
          session: session,
          ecgSamples: const [0.1, 0.2, 0.3],
          finalBpm: 72,
          totalDurationSeconds: 15,
        ),
      ),
    );

    expect(find.text('Symptom Entry Screen'), findsOneWidget);
    expect(find.text('Symptoms (optional)'), findsOneWidget);
    expect(find.text('End Session'), findsOneWidget);
  });

  testWidgets('History screen is the patient session history screen',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PatientSessionHistoryScreen()),
    );

    expect(find.text('Patient Session History Screen'), findsOneWidget);
  });
}
