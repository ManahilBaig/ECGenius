import 'package:flutter/material.dart';

class ECGChart extends StatelessWidget {
  final bool monitoring;
  final List<double> samples;

  const ECGChart({
    required this.monitoring,
    required this.samples,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
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
                'ECG Waveform',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: monitoring
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
                        color: monitoring ? Colors.red : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      monitoring ? 'Recording' : 'Recorded',
                      style: TextStyle(
                        color: monitoring ? Colors.red : Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRect(
              child: CustomPaint(
                painter: ECGPainter(samples: samples),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ECGPainter extends CustomPainter {
  final List<double> samples;

  ECGPainter({required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    if (samples.length < 2) {
      return;
    }

    final path = Path();
    final visibleSamples =
        samples.length > 720 ? samples.sublist(samples.length - 720) : samples;
    final dx = size.width / (visibleSamples.length - 1);
    final midY = size.height / 2;
    const amplitude = 42.0;

    for (var i = 0; i < visibleSamples.length; i++) {
      final x = i * dx;
      final y = midY - (visibleSamples[i] * amplitude);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;

    for (var x = 0.0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ECGPainter oldDelegate) {
    return true;
  }
}
