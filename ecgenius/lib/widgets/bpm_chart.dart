import 'dart:async';
import 'package:flutter/material.dart';

class BPMChart extends StatefulWidget {
  final bool monitoring;
  final int bpm;
  const BPMChart({required this.monitoring, required this.bpm, super.key});

  @override
  State<BPMChart> createState() => _BPMChartState();
}

class _BPMChartState extends State<BPMChart> {
  List<int> bpmHistory = [];
  Timer? timer;

  @override
  void didUpdateWidget(covariant BPMChart oldWidget) {
    if (widget.monitoring && timer == null) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          // Add current BPM to history
          bpmHistory.add(widget.bpm);
          // Keep only last 60 data points (1 minute at 1 second intervals)
          if (bpmHistory.length > 60) {
            bpmHistory.removeAt(0);
          }
        });
      });
    } else if (!widget.monitoring) {
      timer?.cancel();
      timer = null;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BPM Chart',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.monitoring
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.monitoring ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.monitoring ? 'Live' : 'Stopped',
                      style: TextStyle(
                        color: widget.monitoring ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: bpmHistory.isEmpty
                ? Center(
                    child: Text(
                      'No data yet',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: BPMChartPainter(bpmHistory),
                    child: Container(),
                  ),
          ),
        ],
      ),
    );
  }
}

class BPMChartPainter extends CustomPainter {
  final List<int> bpmHistory;

  BPMChartPainter(this.bpmHistory);

  @override
  void paint(Canvas canvas, Size size) {
    if (bpmHistory.length < 2) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final minBPM = 40.0;
    final maxBPM = 160.0;
    final range = maxBPM - minBPM;

    Path path = Path();

    for (int i = 0; i < bpmHistory.length; i++) {
      final x = (i / (bpmHistory.length - 1)) * size.width;
      final y = size.height -
          ((bpmHistory[i] - minBPM) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw axis lines
    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), axisPaint);
  }

  @override
  bool shouldRepaint(BPMChartPainter oldDelegate) {
    return oldDelegate.bpmHistory != bpmHistory;
  }
}
