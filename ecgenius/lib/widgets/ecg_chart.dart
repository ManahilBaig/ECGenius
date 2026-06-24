import 'dart:async';
import 'dart:math' show Random, sin, pi;
import 'package:flutter/material.dart';

class ECGChart extends StatefulWidget {
  final bool monitoring;
  const ECGChart({required this.monitoring, super.key});

  @override
  State<ECGChart> createState() => _ECGChartState();
}

class _ECGChartState extends State<ECGChart> {
  List<double> points = [];
  Timer? timer;
  final Random _random = Random();

  @override
  void didUpdateWidget(covariant ECGChart oldWidget) {
    if (widget.monitoring && timer == null) {
      timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        setState(() {
          // Generate ECG-like waveform
          double value = _generateECGPoint(points.length);
          points.add(value);
          if (points.length > 200) points.removeAt(0);
        });
      });
    } else if (!widget.monitoring) {
      timer?.cancel();
      timer = null;
      if (points.isNotEmpty) {
        setState(() {
          points.clear();
        });
      }
    }
    super.didUpdateWidget(oldWidget);
  }

  double _generateECGPoint(int index) {
    // Generate a more realistic ECG waveform
    double x = index * 0.1;
    double value = 0.0;

    // P wave
    if (x % 1.0 < 0.1) {
      value = 0.3 * sin((x % 1.0) * 10 * pi);
    }
    // QRS complex
    else if (x % 1.0 >= 0.1 && x % 1.0 < 0.2) {
      double t = (x % 1.0 - 0.1) * 10;
      value = -0.5 * sin(t * pi) + 1.5 * sin(t * 2 * pi);
    }
    // T wave
    else if (x % 1.0 >= 0.2 && x % 1.0 < 0.4) {
      double t = (x % 1.0 - 0.2) * 5;
      value = 0.4 * sin(t * pi);
    }
    // Baseline with small noise
    else {
      value = 0.1 * _random.nextDouble() - 0.05;
    }

    return value;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "ECG Waveform",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.monitoring
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.monitoring ? Colors.red : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.monitoring ? 'Recording' : 'Idle',
                      style: TextStyle(
                        color: widget.monitoring ? Colors.red : Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CustomPaint(
              painter: ECGPainter(points),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}

class ECGPainter extends CustomPainter {
  final List<double> points;

  ECGPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.1)
      ..strokeWidth = 1.0;

    for (int i = 0; i < size.width; i += 20) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(i.toDouble(), size.height),
        gridPaint,
      );
    }

    for (int i = 0; i < size.height; i += 20) {
      canvas.drawLine(
        Offset(0, i.toDouble()),
        Offset(size.width, i.toDouble()),
        gridPaint,
      );
    }

    // Draw waveform
    final wavePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.isNotEmpty) {
      Path path = Path();
      for (int i = 0; i < points.length; i++) {
        final x = (i / points.length) * size.width;
        final y = size.height / 2 - (points[i] * size.height / 4);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    }

    // Draw center baseline
    final baselinePaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baselinePaint,
    );
  }

  @override
  bool shouldRepaint(ECGPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
