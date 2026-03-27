import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';

class DiagonalLinePainter extends CustomPainter {
  final List<double>? dataPoints; // Optional: for real data later
  final int? selectedPointIndex;

  DiagonalLinePainter({this.dataPoints, this.selectedPointIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    // Don't draw anything if no real data is provided
    if (dataPoints == null || dataPoints!.isEmpty) return;

    final paint = Paint()
      ..color = AppTheme.chartLineColor
      ..strokeWidth = 1.33
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    // Use only real data - no sample points
    final points = dataPoints!;

    if (points.isEmpty) return;

    // Calculate step size to ensure all points are distributed across full width
    // Always use full width regardless of number of points
    final pointCount = points.length;
    final stepSize = pointCount > 1 ? size.width / (pointCount - 1) : 0.0;

    // Start the path at the first point (x=0, always)
    // Y coordinate: higher normalized values (maxPrice = 1.0) should be at top (y=0)
    // Lower normalized values (minPrice = 0.0) should be at bottom (y=height)
    // So we invert: y = height - (normalizedValue * height)
    final startY = size.height - (points[0] * size.height);
    path.moveTo(0, startY);

    // Handle single point case - draw a horizontal line
    if (pointCount == 1) {
      path.lineTo(size.width, startY);
    } else {
      // Create smooth curve through all points using cubic bezier
      // Always distribute all points across the full width
      for (int i = 1; i < pointCount; i++) {
        // Calculate x position: always span from 0 to full width
        final x = i * stepSize;
        // Invert Y so higher values appear at top
        final y = size.height - (points[i] * size.height);

        if (i == 1) {
          // First segment: use quadratic curve
          final controlX = x * 0.5;
          final controlY = size.height -
              (points[0] * size.height) * 0.7 -
              (points[i] * size.height) * 0.3;
          path.quadraticBezierTo(controlX, controlY, x, y);
        } else {
          // Subsequent segments: use cubic bezier for smooth transitions
          final prevX = (i - 1) * stepSize;
          final prevY = size.height - (points[i - 1] * size.height);

          // Control points for smooth curve
          final cp1X = prevX + (x - prevX) * 0.3;
          final cp1Y = prevY;
          final cp2X = prevX + (x - prevX) * 0.7;
          final cp2Y = y;

          path.cubicTo(cp1X, cp1Y, cp2X, cp2Y, x, y);
        }
      }

      // Ensure the last point reaches the full width
      if (pointCount > 1) {
        final lastX = (pointCount - 1) * stepSize;
        if (lastX < size.width) {
          final lastY = size.height - (points[pointCount - 1] * size.height);
          path.lineTo(size.width, lastY);
        }
      }
    }

    canvas.drawPath(path, paint);

    // Draw selected point highlight if a point is selected
    if (selectedPointIndex != null &&
        selectedPointIndex! >= 0 &&
        selectedPointIndex! < pointCount) {
      final selectedX = selectedPointIndex! * stepSize;
      final selectedY =
          size.height - (points[selectedPointIndex!] * size.height);

      // Draw 5px black square with 1.33px white stroke
      const squareSize = 5.0;
      final squareRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(selectedX, selectedY),
          width: squareSize,
          height: squareSize,
        ),
        Radius.zero,
      );

      // Draw fill
      final fillPaint = Paint()
        ..color = AppTheme.dotFillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(squareRect, fillPaint);

      // Draw stroke
      final strokePaint = Paint()
        ..color = AppTheme.dotStrokeColor
        ..strokeWidth = 1.33
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(squareRect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(DiagonalLinePainter oldDelegate) {
    return oldDelegate.dataPoints != dataPoints ||
        oldDelegate.selectedPointIndex != oldDelegate.selectedPointIndex;
  }
}

