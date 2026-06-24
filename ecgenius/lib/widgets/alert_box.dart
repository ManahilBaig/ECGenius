import 'package:flutter/material.dart';

class AlertBox extends StatelessWidget {
  final int bpm;
  const AlertBox({required this.bpm, super.key});

  @override
  Widget build(BuildContext context) {
    if (bpm >= 60 && bpm <= 100) return const SizedBox();

    final isHigh = bpm > 100;
    final color = isHigh ? Colors.orange : Colors.blue;
    final message = isHigh
        ? "Elevated Heart Rate Detected"
        : "Low Heart Rate Detected";
    final description = isHigh
        ? "Heart rate is above normal range. Please consult a healthcare provider."
        : "Heart rate is below normal range. Please consult a healthcare provider.";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: color[900],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: color[800], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
