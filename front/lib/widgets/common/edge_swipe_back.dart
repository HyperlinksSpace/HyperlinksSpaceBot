import 'package:flutter/material.dart';

/// Wraps a page body and triggers [onBack] when the user swipes from the left
/// edge of the screen (same as back button / previous page).
///
/// Uses an overlay strip on the left so the gesture wins over scrollables
/// (e.g. SingleChildScrollView on the trade page). Only touches that start
/// in the left [edgeWidth] pixels are handled. Back is triggered when the
/// horizontal drag to the right exceeds [minDragDistance] or when the drag
/// velocity is rightward.
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    super.key,
    required this.child,
    required this.onBack,
    this.edgeWidth = 24.0,
    this.minDragDistance = 50.0,
  });

  final Widget child;
  final VoidCallback onBack;
  final double edgeWidth;
  final double minDragDistance;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  bool _isTracking = false;
  double _dragDelta = 0.0;

  void _onHorizontalDragStart(DragStartDetails details) {
    setState(() {
      _isTracking = true;
      _dragDelta = 0.0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isTracking) return;
    setState(() {
      _dragDelta += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isTracking) return;
    final triggerByDistance = _dragDelta >= widget.minDragDistance;
    final triggerByVelocity = details.primaryVelocity != null &&
        details.primaryVelocity! > 300;
    if (triggerByDistance || triggerByVelocity) {
      widget.onBack();
    }
    setState(() {
      _isTracking = false;
      _dragDelta = 0.0;
    });
  }

  void _onHorizontalDragCancel() {
    setState(() {
      _isTracking = false;
      _dragDelta = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main content (receives all taps/scrolls outside the edge strip)
        Positioned.fill(child: widget.child),
        // Invisible strip on the left that wins hit-test; captures edge swipe
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: _onHorizontalDragCancel,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
