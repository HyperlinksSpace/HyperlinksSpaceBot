import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui show TextDirection;
import 'package:http/http.dart' as http;
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../app/theme/app_theme.dart';
import '../widgets/global/global_logo_bar.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/common/pointer_region.dart';
import '../widgets/common/diagonal_line_painter.dart';
import '../telegram_safe_area.dart';
import '../telegram_webapp.dart';
import '../utils/app_haptic.dart';
import 'wallets_page.dart';

class SwapPage extends StatefulWidget {
  const SwapPage({super.key});

  @override
  State<SwapPage> createState() => _SwapPageState();
}

class _SwapPageState extends State<SwapPage> {
  // Helper method to calculate adaptive bottom padding
  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();

    // Formula: bottom SafeAreaInset + 30px
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }

  // Helper method to calculate GlobalBottomBar height
  // GlobalBottomBar structure:
  // - Container padding: top: 10, bottom: 15 (total 25px)
  // - TextField minHeight: 30px
  double _getGlobalBottomBarHeight() {
    // Minimum height: container padding (10 + 15) + TextField minHeight (30)
    return 10.0 + 30.0 + 15.0;
  }
  
  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  
  StreamSubscription<tma.BackButton>? _backButtonSubscription;

  // Chart data
  List<double>? _chartDataPoints;
  bool _isLoadingChart = true;
  String? _chartError; // Error message for chart loading
  String _selectedResolution = 'day1'; // Default: day1 (d)
  double? _chartMinPrice;
  double? _chartMaxPrice;
  DateTime? _chartFirstTimestamp;
  DateTime? _chartLastTimestamp;

  // Original chart data for point selection (prices and timestamps)
  List<Map<String, dynamic>>? _originalChartData;

  // Selected point for interactive chart
  int? _selectedPointIndex;

  // Rate limiting for dyor API (1 call per second)
  DateTime? _lastChartApiCall;
  int _chartRetryCount = 0;
  static const int _maxRetries = 5;
  static const Duration _rateLimitDelay = Duration(seconds: 1);

  // TON address for default pair
  static const String _tonAddress =
      '0:0000000000000000000000000000000000000000000000000000000000000000';
  static const String _chartApiUrl = 'https://api.dyor.io';
  static const String _swapCoffeeApiUrl = 'https://backend.swap.coffee';
  // USDT contract address on TON blockchain
  static const String _usdtAddress =
      'EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs';

  // Swap state variables
  final String _buyCurrency = 'TON';
  final double _buyAmount = 1.0; // Default: 1 TON
  final String _sellCurrency = 'DLLR';
  double? _sellAmount; // Will be fetched from API
  bool _isLoadingSwapAmount = false;
  String? _usdtTokenAddress; // Will be fetched from API if needed
  String? _swapAmountError; // Error message if fetch fails

  // Market stats state variables
  static const String _tokensApiUrl = 'https://tokens.swap.coffee';
  double? _priceUsd; // Current price in USD
  double? _mcap;
  double? _fdmc;
  double? _volume24h;
  double? _priceChange5m;
  double? _priceChange1h;
  double? _priceChange6h;
  double? _priceChange24h;

  // Resolution mapping: button -> API value
  static const Map<String, String> _resolutionMap = {
    'd': 'day1',
    'h': 'hour1',
    'q': 'min15',
    'm': 'min1',
  };

  static const List<String> _resolutionOrder = ['d', 'h', 'q', 'm'];
  static const double _resolutionSwipeVelocityThreshold = 200.0;
  // Keep screen edges free so EdgeSwipeBack can handle back gestures.
  static const double _edgeSwipeGuardWidth = 56.0;

  double? _horizontalDragStartX;

  // Maximum time ranges for each resolution (in days)
  static const Map<String, int> _maxTimeRanges = {
    'day1': 365, // 365 days
    'hour1': 30, // 30 days
    'min15': 7, // 7 days
    'min1': 1, // 24 hours = 1 day
  };

  /// Calculate the time range for the selected resolution
  /// Returns a map with 'from' and 'to' as ISO 8601 strings
  Map<String, String> _getTimeRange() {
    final now = DateTime.now().toUtc();
    final maxDays = _maxTimeRanges[_selectedResolution] ?? 30;

    // Calculate 'from' date: maxDays ago
    final from = now.subtract(Duration(days: maxDays));

    return {
      'from': from.toIso8601String(),
      'to': now.toIso8601String(),
    };
  }

  /// Handle chart pointer to find closest point using hybrid method:
  /// - If pointer is close to chart: use Euclidean distance (x and y) for precise selection
  /// - If pointer is far from chart: use x-axis only for quick selection
  void _handleChartPointer(Offset localPosition, Size chartSize) {
    if (_chartDataPoints == null ||
        _chartDataPoints!.isEmpty ||
        _originalChartData == null) {
      return;
    }

    final pointCount = _chartDataPoints!.length;
    if (pointCount == 0) return;

    // Validate chart size
    if (chartSize.width <= 0 || chartSize.height <= 0) {
      return;
    }

    // Calculate step size (same as in painter)
    final stepSize = pointCount > 1 ? chartSize.width / (pointCount - 1) : 0.0;

    // First, find the closest point by x-axis to determine proximity
    int closestByX = 0;
    double minXDistance = double.infinity;

    for (int i = 0; i < pointCount; i++) {
      final pointX = i * stepSize;
      final xDistance = (localPosition.dx - pointX).abs();
      if (xDistance < minXDistance) {
        minXDistance = xDistance;
        closestByX = i;
      }
    }

    // Calculate the y position of the closest x point to check vertical distance
    final normalizedValue = _chartDataPoints![closestByX];
    final closestPointY =
        chartSize.height - (normalizedValue * chartSize.height);
    final verticalDistance = (localPosition.dy - closestPointY).abs();

    // Threshold: use a combination of fixed pixels and percentage of chart height
    // This ensures reasonable proximity detection for both small and large charts
    // - Minimum: 40 pixels (ensures reasonable proximity even for small charts)
    // - Maximum: 15% of chart height (scales with chart size for larger charts)
    // Result: uses whichever is larger, so small charts get at least 40px, large charts scale up
    // This means: if pointer is within ~40-60px of the chart line, use precise Euclidean selection
    const fixedThreshold = 40.0; // pixels - minimum threshold
    final percentageThreshold = chartSize.height * 0.15; // 15% of chart height
    final proximityThreshold = math.max(fixedThreshold, percentageThreshold);
    final isCloseToChart = verticalDistance < proximityThreshold;

    int closestIndex;
    if (isCloseToChart) {
      // Close to chart: use Euclidean distance for precise selection
      double minDistance = double.infinity;
      closestIndex = 0;

      for (int i = 0; i < pointCount; i++) {
        final pointX = i * stepSize;
        final normalizedValue = _chartDataPoints![i];
        final pointY = chartSize.height - (normalizedValue * chartSize.height);

        // Calculate Euclidean distance (scalar length)
        final dx = localPosition.dx - pointX;
        final dy = localPosition.dy - pointY;
        final distance = math.sqrt(dx * dx + dy * dy);

        if (distance < minDistance) {
          minDistance = distance;
          closestIndex = i;
        }
      }
    } else {
      // Far from chart: use x-axis only for quick selection
      closestIndex = closestByX;
    }

    // Only update state if the selected index actually changed
    if (_selectedPointIndex != closestIndex) {
      setState(() {
        _selectedPointIndex = closestIndex;
      });
    }
  }

  /// Single "TON rate in dollars" for UI: use chart last price when available (matches chart zone), else market stats.
  double? get _effectiveTonPriceUsd {
    if (_originalChartData != null &&
        _originalChartData!.isNotEmpty &&
        _originalChartData!.last['price'] != null) {
      return (_originalChartData!.last['price'] as num).toDouble();
    }
    return _priceUsd;
  }

  /// Format price value for display (up to 5 decimal places, removing trailing zeros)
  String _formatPrice(double price) {
    // Format to 5 decimal places
    final formatted = price.toStringAsFixed(5);
    // Remove trailing zeros
    if (formatted.contains('.')) {
      return formatted
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');
    }
    return formatted;
  }

  /// Get the resolution label for display
  Widget _buildResolutionButton(String key) {
    final isSelected = _selectedResolution == _resolutionMap[key];
    return GestureDetector(
      onTap: () {
        _setResolutionByKey(key);
      },
      child: Container(
        height: 20,
        width: 30, // Fixed width to prevent layout shifts
        alignment: Alignment.center,
        child: Text(
          key,
          style: TextStyle(
            fontWeight: FontWeight.w500, // Always medium
            color: isSelected 
                ? (AppTheme.isDarkTheme ? const Color(0xFFFAFAFA) : const Color(0xFF111111))
                : const Color(0xFF818181),
            fontSize: 15,
          ),
        ),
      ),
    ).pointer;
  }

  void _setResolutionByKey(String key) {
    final targetResolution = _resolutionMap[key];
    if (targetResolution == null || _selectedResolution == targetResolution) {
      return;
    }

    AppHaptic.heavy();
    setState(() {
      _selectedResolution = targetResolution;
    });
    _fetchChartData();
  }

  void _selectResolutionToLeft() {
    final currentKey = _resolutionMap.entries
        .firstWhere(
          (entry) => entry.value == _selectedResolution,
          orElse: () => const MapEntry('d', 'day1'),
        )
        .key;
    final currentIndex = _resolutionOrder.indexOf(currentKey);
    if (currentIndex > 0) {
      _setResolutionByKey(_resolutionOrder[currentIndex - 1]);
    }
  }

  void _selectResolutionToRight() {
    final currentKey = _resolutionMap.entries
        .firstWhere(
          (entry) => entry.value == _selectedResolution,
          orElse: () => const MapEntry('d', 'day1'),
        )
        .key;
    final currentIndex = _resolutionOrder.indexOf(currentKey);
    if (currentIndex >= 0 && currentIndex < _resolutionOrder.length - 1) {
      _setResolutionByKey(_resolutionOrder[currentIndex + 1]);
    }
  }

  bool _isCenterSwipeStart(double startX, double width) {
    final leftBound = _edgeSwipeGuardWidth;
    final rightBound = width - _edgeSwipeGuardWidth;
    return startX > leftBound && startX < rightBound;
  }

  void _onResolutionSwipeStart(DragStartDetails details) {
    _horizontalDragStartX = details.globalPosition.dx;
  }

  void _onResolutionSwipeEnd(DragEndDetails details, BuildContext context) {
    final startX = _horizontalDragStartX;
    _horizontalDragStartX = null;
    if (startX == null) return;

    final width = MediaQuery.of(context).size.width;
    if (!_isCenterSwipeStart(startX, width)) {
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity > _resolutionSwipeVelocityThreshold) {
      _selectResolutionToLeft(); // swipe right -> previous
    } else if (velocity < -_resolutionSwipeVelocityThreshold) {
      _selectResolutionToRight(); // swipe left -> next
    }
  }

  String _getResolutionLabel() {
    switch (_selectedResolution) {
      case 'day1':
        return '(Day)';
      case 'hour1':
        return '(Hour)';
      case 'min15':
        return '(15m)';
      case 'min1':
        return '(1m)';
      default:
        return '';
    }
  }

  /// Calculate the maximum width needed for price column
  /// Takes into account ALL prices in the chart data to prevent dynamic width changes
  double _calculateMaxPriceWidth() {
    const textStyle = TextStyle(
      color: Color(0xFF818181),
      fontSize: 10,
    );

    double maxWidth = 0.0;
    const textDir = ui.TextDirection.ltr;

    // Check all prices in the chart data to find the widest one
    // This ensures the width doesn't change when pointing at different parts of the chart
    if (_originalChartData != null && _originalChartData!.isNotEmpty) {
      for (final dataPoint in _originalChartData!) {
        final price = dataPoint['price'] as double?;
        if (price != null) {
          final priceText = _formatPrice(price);
          final textPainter = TextPainter(
            text: TextSpan(text: priceText, style: textStyle),
            textDirection: textDir,
          );
          textPainter.layout();
          maxWidth = math.max(maxWidth, textPainter.width);
        }
      }
    } else {
      // Fallback: check min and max prices if original data is not available
      if (_chartMinPrice != null) {
        final minPriceText = _formatPrice(_chartMinPrice!);
        final textPainter = TextPainter(
          text: TextSpan(text: minPriceText, style: textStyle),
          textDirection: textDir,
        );
        textPainter.layout();
        maxWidth = math.max(maxWidth, textPainter.width);
      }

      if (_chartMaxPrice != null) {
        final maxPriceText = _formatPrice(_chartMaxPrice!);
        final textPainter = TextPainter(
          text: TextSpan(text: maxPriceText, style: textStyle),
          textDirection: textDir,
        );
        textPainter.layout();
        maxWidth = math.max(maxWidth, textPainter.width);
      }
    }

    // Add a small padding for safety and return default if no prices
    return maxWidth > 0 ? maxWidth + 2.0 : 60.0;
  }

  /// Format timestamp based on resolution
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final timestampDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    switch (_selectedResolution) {
      case 'day1': // d: DD/MM/YY
        return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year.toString().substring(2)}';

      case 'hour1': // h: DD/MM
        return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}';

      case 'min15': // q: DD/MM HH:mm
        return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      case 'min1': // m: 22:19, yesterday or 22:19, today
        final timeStr =
            '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
        if (timestampDate == today) {
          return '$timeStr, Today';
        } else if (timestampDate == yesterday) {
          return '$timeStr, Yesterday';
        } else {
          // Fallback to date if not today or yesterday
          return '$timeStr, ${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}';
        }

      default:
        return timestamp.toString();
    }
  }

  /// Build selected point timestamp row aligned with the dot
  Widget _buildSelectedPointTimestampRow() {
    if (_selectedPointIndex == null ||
        _originalChartData == null ||
        _selectedPointIndex! >= _originalChartData!.length ||
        _chartDataPoints == null) {
      return const SizedBox.shrink();
    }

    final selectedData = _originalChartData![_selectedPointIndex!];
    final timestamp = selectedData['timestamp'] as DateTime?;
    if (timestamp == null) return const SizedBox.shrink();

    // Build the text widget first to measure it
    Widget timestampTextWidget;
    if (_selectedResolution == 'min1') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final timestampDate =
          DateTime(timestamp.year, timestamp.month, timestamp.day);
      final timeStr =
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      if (timestampDate == today) {
        timestampTextWidget = RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF818181),
              height: 1.0,
            ),
            children: [
              TextSpan(text: timeStr),
              const TextSpan(
                text: ', Today',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      } else if (timestampDate == yesterday) {
        timestampTextWidget = RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF818181),
              height: 1.0,
            ),
            children: [
              TextSpan(text: timeStr),
              const TextSpan(
                text: ', Yesterday',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      } else {
        timestampTextWidget = Text(
          _formatTimestamp(timestamp),
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF818181),
            height: 1.0,
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      }
    } else {
      timestampTextWidget = Text(
        _formatTimestamp(timestamp),
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF818181),
          height: 1.0,
        ),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      );
    }

    // Measure text width and calculate exact positioning
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth.isInfinite) {
          // Fallback to center alignment if constraints are infinite
          return Align(
            alignment: Alignment.center,
            child: timestampTextWidget,
          );
        }

        // Measure text width - need to handle RichText case
        const textStyle = TextStyle(
          fontSize: 10,
          color: Color(0xFF818181),
        );
        TextSpan textSpan;
        if (_selectedResolution == 'min1') {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));
          final timestampDate =
              DateTime(timestamp.year, timestamp.month, timestamp.day);
          final timeStr =
              '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

          if (timestampDate == today) {
            textSpan = TextSpan(
              style: textStyle,
              children: [
                TextSpan(text: timeStr),
                const TextSpan(
                  text: ', Today',
                  style: TextStyle(fontWeight: FontWeight.normal),
                ),
              ],
            );
          } else if (timestampDate == yesterday) {
            textSpan = TextSpan(
              style: textStyle,
              children: [
                TextSpan(text: timeStr),
                const TextSpan(
                  text: ', Yesterday',
                  style: TextStyle(fontWeight: FontWeight.normal),
                ),
              ],
            );
          } else {
            textSpan = TextSpan(
              text: _formatTimestamp(timestamp),
              style: textStyle,
            );
          }
        } else {
          textSpan = TextSpan(
            text: _formatTimestamp(timestamp),
            style: textStyle,
          );
        }

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        final textWidth = textPainter.width;

        // Calculate dot's x position on the chart
        final pointCount = _chartDataPoints!.length;
        final xRatio =
            pointCount > 1 ? _selectedPointIndex! / (pointCount - 1) : 0.0;
        final dotX = xRatio * constraints.maxWidth;

        // Calculate where text center should be (at dot position)
        final textCenterX = dotX;
        final textLeft = textCenterX - (textWidth / 2);
        final textRight = textCenterX + (textWidth / 2);

        // Determine final alignment: center on dot unless text would overflow
        double finalAlignmentX;
        if (textLeft < 0) {
          // Text would overflow left edge - stick to left
          finalAlignmentX = -1.0;
        } else if (textRight > constraints.maxWidth) {
          // Text would overflow right edge - stick to right
          finalAlignmentX = 1.0;
        } else {
          // Text fits - center on dot
          finalAlignmentX = 0.0;
        }

        // Use Transform to position text exactly at dot when centered
        if (finalAlignmentX == 0.0) {
          // Center on dot: calculate offset to move text center to dot position
          final offsetX = dotX - (constraints.maxWidth / 2);
          return Transform.translate(
            offset: Offset(offsetX, 0),
            child: Center(
              child: timestampTextWidget,
            ),
          );
        } else {
          // Edge case: align to edge
          return Align(
            alignment: Alignment(finalAlignmentX, 0.0),
            child: timestampTextWidget,
          );
        }
      },
    );
  }

  /// Build normal price column with max and min prices positioned at exact chart points
  Widget _buildNormalPriceColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight || constraints.maxHeight.isInfinite) {
          // Fallback to spaceBetween if constraints are infinite
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _chartMaxPrice != null
                    ? _formatPrice(_chartMaxPrice!)
                    : "0.00000",
                style: const TextStyle(
                  color: Color(0xFF818181),
                  fontSize: 10,
                ),
                textAlign: TextAlign.right,
              ),
              Text(
                _chartMinPrice != null
                    ? _formatPrice(_chartMinPrice!)
                    : "0.00000",
                style: const TextStyle(
                  color: Color(0xFF818181),
                  fontSize: 10,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          );
        }

        const textHeightBehavior = TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        );

        // Calculate positions: max price is at top (normalizedValue = 1.0 -> y = 0)
        // min price is at bottom (normalizedValue = 0.0 -> y = height)
        const maxPriceY = 0.0; // Max price is at top of chart
        final minPriceY =
            constraints.maxHeight; // Min price is at bottom of chart

        final maxPriceText =
            _chartMaxPrice != null ? _formatPrice(_chartMaxPrice!) : "0.00000";
        final minPriceText =
            _chartMinPrice != null ? _formatPrice(_chartMinPrice!) : "0.00000";

        // Use the same text center offset as selected point price for consistency
        const textCenterOffset = 4.5; // Same as selected point price

        // Position max price: center it at y = 0 (top)
        // textTop + textCenterOffset = 0, so textTop = -textCenterOffset
        // But we need to clamp to 0 if it would go negative
        const maxPriceTop = maxPriceY - textCenterOffset;
        const maxPriceTopClamped = maxPriceTop < 0 ? 0.0 : maxPriceTop;

        // Position min price: center it at y = height (bottom)
        // textTop + textCenterOffset = height, so textTop = height - textCenterOffset
        final minPriceTop = minPriceY - textCenterOffset;
        // Clamp to ensure text doesn't overflow bottom
        final minPriceTopClamped =
            (minPriceTop + textCenterOffset * 2) > constraints.maxHeight
                ? constraints.maxHeight - (textCenterOffset * 2)
                : minPriceTop;

        return Stack(
          children: [
            // Max price at top
            Positioned(
              top: maxPriceTopClamped,
              left: 0,
              right: 0,
              child: Text(
                maxPriceText,
                style: const TextStyle(
                  color: Color(0xFF818181),
                  fontSize: 10,
                  height: 1.0,
                ),
                textAlign: TextAlign.right,
                textHeightBehavior: textHeightBehavior,
              ),
            ),
            // Min price at bottom
            Positioned(
              top: minPriceTopClamped,
              left: 0,
              right: 0,
              child: Text(
                minPriceText,
                style: const TextStyle(
                  color: Color(0xFF818181),
                  fontSize: 10,
                  height: 1.0,
                ),
                textAlign: TextAlign.right,
                textHeightBehavior: textHeightBehavior,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build selected point price column aligned with the dot
  Widget _buildSelectedPointPriceColumn() {
    if (_selectedPointIndex == null ||
        _originalChartData == null ||
        _selectedPointIndex! >= _originalChartData!.length ||
        _chartDataPoints == null) {
      return const SizedBox.shrink();
    }

    final selectedData = _originalChartData![_selectedPointIndex!];
    final price = selectedData['price'] as double?;
    if (price == null) return const SizedBox.shrink();

    final priceText = _formatPrice(price);
    final priceTextWidget = Text(
      priceText,
      style: const TextStyle(
        color: Color(0xFF818181),
        fontSize: 10,
        height: 1.0,
      ),
      textAlign: TextAlign.right,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );

    // Measure text height and calculate exact positioning
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight || constraints.maxHeight.isInfinite) {
          // Fallback to center alignment if constraints are infinite
          return Align(
            alignment: Alignment.center,
            child: priceTextWidget,
          );
        }

        // Measure text height - use the same text style as the widget
        const textStyle = TextStyle(
          fontSize: 10,
          color: Color(0xFF818181),
          height: 1.0,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: priceText, style: textStyle),
          textDirection: ui.TextDirection.ltr,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
        textPainter.layout();

        // Get the actual visual center of the text
        // With textHeightBehavior (applyHeightToFirstAscent: false, applyHeightToLastDescent: false)
        // and height: 1.0, fontSize 10 should render as approximately 10px tall
        // The visual center might be slightly less than fontSize/2 due to how text renders
        // If text appears below dot, the center offset is too large - using a smaller value
        // Adjust this value: if text is below dot, decrease it; if above, increase it
        const textCenterOffset =
            4.5; // Slightly less than 5px (fontSize/2) to account for text rendering

        // Calculate dot's y position on the chart
        // normalizedValue: 0.0 = min (bottom), 1.0 = max (top)
        final normalizedValue = _chartDataPoints![_selectedPointIndex!];
        // Y coordinate: invert so higher values appear at top
        // This matches exactly how the dot is drawn in the painter:
        // selectedY = size.height - (points[selectedPointIndex!] * size.height)
        final dotY =
            constraints.maxHeight - (normalizedValue * constraints.maxHeight);

        // Calculate where text top should be so its center aligns with dot
        // The dot's center is at dotY, so we want the text's center at dotY
        // textTop + textCenterOffset = dotY
        // Therefore: textTop = dotY - textCenterOffset
        // Note: If text appears below dot, textCenterOffset might be too large
        // If text appears above dot, textCenterOffset might be too small
        final textTop = dotY - textCenterOffset;
        final textBottom = dotY + textCenterOffset;

        // Determine final alignment: center on dot unless text would overflow
        double finalAlignmentY;
        if (textTop < 0) {
          // Text would overflow top edge - stick to top
          finalAlignmentY = -1.0;
        } else if (textBottom > constraints.maxHeight) {
          // Text would overflow bottom edge - stick to bottom
          finalAlignmentY = 1.0;
        } else {
          // Text fits - center on dot
          finalAlignmentY = 0.0;
        }

        // Use Stack with Positioned for precise positioning
        if (finalAlignmentY == 0.0) {
          // Center on dot: position text so its visual center aligns with dot
          // The text's visual center should be at dotY
          // We position the text at textTop so that textTop + textCenterOffset = dotY
          // textTop = dotY - 5 (for fontSize 10, center is at 5px from top)
          return Stack(
            children: [
              Positioned(
                top: textTop,
                left: 0,
                right: 0,
                child: priceTextWidget,
              ),
            ],
          );
        } else {
          // Edge case: align to edge
          return Align(
            alignment: Alignment(0.0, finalAlignmentY),
            child: priceTextWidget,
          );
        }
      },
    );
  }

  /// Build timestamp widget with proper styling for min1 resolution
  Widget _buildTimestampWidget(DateTime? timestamp) {
    Widget textWidget;

    if (timestamp == null) {
      textWidget = const Text(
        "--/--",
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFF818181),
          height: 1.0, // Fixed line height to prevent layout shift
        ),
        textHeightBehavior: TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      );
    } else if (_selectedResolution == 'min1') {
      // For min1 resolution, use RichText to style "Today"/"Yesterday" with regular font weight
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final timestampDate =
          DateTime(timestamp.year, timestamp.month, timestamp.day);
      final timeStr =
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      if (timestampDate == today) {
        textWidget = RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF818181),
              height: 1.0, // Fixed line height to prevent layout shift
            ),
            children: [
              TextSpan(text: timeStr),
              const TextSpan(
                text: ', Today',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      } else if (timestampDate == yesterday) {
        textWidget = RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF818181),
              height: 1.0, // Fixed line height to prevent layout shift
            ),
            children: [
              TextSpan(text: timeStr),
              const TextSpan(
                text: ', yesterday',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      } else {
        // Fallback for min1
        textWidget = Text(
          _formatTimestamp(timestamp),
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF818181),
            height: 1.0, // Fixed line height to prevent layout shift
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        );
      }
    } else {
      // For other resolutions, check if we should show special labels
      String displayText;
      
      // Check if this is the first (oldest) timestamp and we have a last (newest) timestamp
      if (_chartFirstTimestamp != null && 
          _chartLastTimestamp != null && 
          timestamp.year == _chartFirstTimestamp!.year &&
          timestamp.month == _chartFirstTimestamp!.month &&
          timestamp.day == _chartFirstTimestamp!.day &&
          timestamp.hour == _chartFirstTimestamp!.hour &&
          timestamp.minute == _chartFirstTimestamp!.minute) {
        
        // Check if first timestamp is exactly one year ago from last timestamp (Day resolution)
        if (_selectedResolution == 'day1') {
          final oneYearAgo = DateTime(
            _chartLastTimestamp!.year - 1,
            _chartLastTimestamp!.month,
            _chartLastTimestamp!.day,
          );
          final firstDate = DateTime(
            _chartFirstTimestamp!.year,
            _chartFirstTimestamp!.month,
            _chartFirstTimestamp!.day,
          );
          
          if (firstDate.year == oneYearAgo.year &&
              firstDate.month == oneYearAgo.month &&
              firstDate.day == oneYearAgo.day) {
            displayText = 'A Year Ago';
          } else {
            displayText = _formatTimestamp(timestamp);
          }
        }
        // Check if first timestamp is exactly one month ago from last timestamp (Hour resolution)
        else if (_selectedResolution == 'hour1') {
          final lastDate = DateTime(
            _chartLastTimestamp!.year,
            _chartLastTimestamp!.month,
            _chartLastTimestamp!.day,
          );
          // Calculate one month ago, handling year rollover
          final oneMonthAgo = lastDate.month == 1
              ? DateTime(lastDate.year - 1, 12, lastDate.day)
              : DateTime(lastDate.year, lastDate.month - 1, lastDate.day);
          final firstDate = DateTime(
            _chartFirstTimestamp!.year,
            _chartFirstTimestamp!.month,
            _chartFirstTimestamp!.day,
          );
          
          if (firstDate.year == oneMonthAgo.year &&
              firstDate.month == oneMonthAgo.month &&
              firstDate.day == oneMonthAgo.day) {
            displayText = 'A Month Ago';
          } else {
            displayText = _formatTimestamp(timestamp);
          }
        } else {
          displayText = _formatTimestamp(timestamp);
        }
      } else {
        displayText = _formatTimestamp(timestamp);
      }
      
      textWidget = Text(
        displayText,
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF818181),
          fontWeight: FontWeight.normal,
          height: 1.0, // Fixed line height to prevent layout shift
        ),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      );
    }

    // Wrap in Align to ensure consistent vertical centering
    // Use textHeightBehavior to prevent baseline shifts
    return Align(
      alignment: Alignment.centerLeft,
      child: textWidget,
    );
  }

  @override
  void initState() {
    super.initState();

    // Fetch chart data on page load
    _fetchChartData();
    // Fetch swap amount on page load
    _fetchSwapAmount();
    // Fetch market stats on page load
    _fetchMarketStats();
    
    // Set up back button using flutter_telegram_miniapp package
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final webApp = tma.WebApp();
        final eventHandler = webApp.eventHandler;
        
        // IMPORTANT: Register listener BEFORE showing the button
        // Listen to backButtonClicked event
        _backButtonSubscription = eventHandler.backButtonClicked.listen((backButton) {
          print('[SwapPage] Back button clicked!');
          _handleBackButton();
        });
        
        print('[SwapPage] Back button listener registered');
        
        // Also set up fallback using direct TelegramWebApp API
        try {
          final telegramWebApp = TelegramWebApp();
          telegramWebApp.onBackButtonClick(() {
            print('[SwapPage] Back button clicked (fallback)!');
            _handleBackButton();
          });
          print('[SwapPage] Fallback back button listener registered');
        } catch (e) {
          print('[SwapPage] Error setting up fallback back button: $e');
        }
        
        // Show the back button after a short delay to ensure listener is ready
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            if (mounted) {
              webApp.backButton.show();
              print('[SwapPage] Back button shown');
            }
          } catch (e) {
            print('[SwapPage] Error showing back button: $e');
          }
        });
      } catch (e) {
        print('[SwapPage] Error setting up back button: $e');
      }
    });
  }
  
  @override
  void dispose() {
    _backButtonSubscription?.cancel();
    
    // Hide back button when leaving swap page
    try {
      tma.WebApp().backButton.hide();
    } catch (e) {
      // Ignore errors
    }
    
    super.dispose();
  }

  Future<void> _fetchChartData({bool isRetry = false}) async {
    // Respect rate limiting: 1 call per second
    if (_lastChartApiCall != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastChartApiCall!);
      if (timeSinceLastCall < _rateLimitDelay) {
        final waitTime = _rateLimitDelay - timeSinceLastCall;
        print(
            'Rate limiting: waiting ${waitTime.inMilliseconds}ms before API call');
        await Future.delayed(waitTime);
      }
    }

    if (!isRetry) {
      setState(() {
        _isLoadingChart = true;
        _chartError = null;
        _chartRetryCount = 0;
      });
    }

    _lastChartApiCall = DateTime.now();

    try {
      // Get time range for the selected resolution
      final timeRange = _getTimeRange();

      // Build API URL with query parameters
      // Using selected resolution, USD currency, and max time range
      final uri = Uri.parse('$_chartApiUrl/v1/jettons/$_tonAddress/price/chart')
          .replace(queryParameters: {
        'resolution': _selectedResolution,
        'currency': 'usd',
        'from': timeRange['from']!,
        'to': timeRange['to']!,
      });

      print('Fetching chart data from: $uri (attempt ${_chartRetryCount + 1})');
      final response = await http.get(uri);
      print('Chart API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Chart API response data keys: ${data.keys.toList()}');
        final points = data['points'] as List<dynamic>?;
        print('Chart points count: ${points?.length ?? 0}');

        if (points != null && points.isNotEmpty) {
          // Extract and convert price values along with timestamps
          // Collect data points with both valid price and timestamp
          var priceDataPoints = <Map<String, dynamic>>[];
          print('Parsing ${points.length} chart points...');
          for (var point in points) {
            try {
              final valueObj = point['value'];
              if (valueObj == null) {
                print('Warning: point missing value field: $point');
                continue;
              }

              final valueStr = valueObj['value'] as String?;
              final decimals = valueObj['decimals'] as int?;

              if (valueStr == null || decimals == null) {
                print('Warning: value or decimals missing in point: $point');
                continue;
              }

              // Extract timestamp
              final timeStr = point['time'] as String?;
              if (timeStr == null) {
                print('Warning: point missing time field: $point');
                continue;
              }

              // Convert to real value: value * 10^(-decimals)
              final value = int.parse(valueStr);
              final realValue = value * math.pow(10, -decimals);

              // Parse timestamp
              DateTime? timestamp;
              try {
                timestamp = DateTime.parse(timeStr).toLocal();
              } catch (e) {
                print('Error parsing timestamp: $e, timeStr: $timeStr');
                continue;
              }

              priceDataPoints.add({
                'price': realValue.toDouble(),
                'timestamp': timestamp,
              });
            } catch (e) {
              print('Error parsing chart point: $e, point: $point');
              continue;
            }
          }

          print(
              'Successfully parsed ${priceDataPoints.length} data points from ${points.length} points');

          if (priceDataPoints.isEmpty) {
            print(
                'Error: No valid data points could be parsed from chart data');
            _handleChartError('No price data available');
            return;
          }

          // Reverse the array - API likely returns newest-first, but we need oldest-first for chart
          priceDataPoints = priceDataPoints.reversed.toList();

          // Store original data for point selection
          setState(() {
            _originalChartData =
                List<Map<String, dynamic>>.from(priceDataPoints);
            _selectedPointIndex = null;
          });

          // Extract prices and timestamps from valid data points
          var prices =
              priceDataPoints.map((dp) => dp['price'] as double).toList();

          // Extract timestamps from actual first and last valid data points
          DateTime? firstTimestamp;
          DateTime? lastTimestamp;

          if (priceDataPoints.isNotEmpty) {
            firstTimestamp = priceDataPoints.first['timestamp'] as DateTime?;
            lastTimestamp = priceDataPoints.last['timestamp'] as DateTime?;
            print(
                'Extracted timestamps - First: $firstTimestamp, Last: $lastTimestamp');
            if (firstTimestamp != null && lastTimestamp != null) {
              final duration = lastTimestamp.difference(firstTimestamp);
              print(
                  'Time range: ${duration.inDays} days, ${duration.inHours % 24} hours, ${duration.inMinutes % 60} minutes');
            }
          }

          // Normalize prices to 0.0-1.0 range for chart display
          if (prices.isNotEmpty) {
            final minPrice = prices.reduce(math.min);
            final maxPrice = prices.reduce(math.max);
            final range = maxPrice - minPrice;

            if (range > 0) {
              // Normalize prices to 0.0-1.0 range for chart display
              // minPrice -> 0.0, maxPrice -> 1.0
              final normalizedPoints = prices.map((price) {
                return (price - minPrice) / range;
              }).toList();

              setState(() {
                _chartDataPoints = normalizedPoints;
                _chartMinPrice = minPrice;
                _chartMaxPrice = maxPrice;
                _chartFirstTimestamp = firstTimestamp;
                _chartLastTimestamp = lastTimestamp;
                _isLoadingChart = false;
                _chartError = null;
                _chartRetryCount = 0;
              });
            } else {
              // All prices are the same, set to middle
              setState(() {
                _chartDataPoints = List.filled(prices.length, 0.5);
                _chartMinPrice = minPrice;
                _chartMaxPrice = maxPrice;
                _chartFirstTimestamp = firstTimestamp;
                _chartLastTimestamp = lastTimestamp;
                _isLoadingChart = false;
                _chartError = null;
                _chartRetryCount = 0;
              });
            }
          } else {
            setState(() {
              _chartDataPoints = null;
              _chartMinPrice = null;
              _chartMaxPrice = null;
              _chartFirstTimestamp = null;
              _chartLastTimestamp = null;
              _isLoadingChart = false;
            });
          }
        } else {
          _handleChartError('No chart data points received');
        }
      } else if (response.statusCode == 429) {
        // Rate limit exceeded - retry with longer delay
        print('Rate limit exceeded (429), retrying...');
        _handleChartErrorWithRetry('Rate limit exceeded. Retrying...');
      } else {
        // Other HTTP errors
        print('Chart fetch failed: ${response.statusCode}');
        _handleChartErrorWithRetry(
            'Failed to load chart (${response.statusCode})');
      }
    } catch (e) {
      print('Chart fetch error: $e');
      _handleChartErrorWithRetry('Network error: ${e.toString()}');
    }
  }

  void _handleChartError(String error) {
    setState(() {
      _chartDataPoints = null;
      _chartMinPrice = null;
      _chartMaxPrice = null;
      _chartFirstTimestamp = null;
      _chartLastTimestamp = null;
      _isLoadingChart = false;
      _chartError = error;
    });
  }

  void _handleChartErrorWithRetry(String error) {
    if (_chartRetryCount < _maxRetries) {
      _chartRetryCount++;
      // Exponential backoff: 1s, 2s, 4s, 8s, 16s
      final backoffDelay =
          Duration(seconds: math.pow(2, _chartRetryCount - 1).toInt());
      print(
          'Retrying chart fetch in ${backoffDelay.inSeconds}s (attempt $_chartRetryCount/$_maxRetries)');

      setState(() {
        _chartError = '$error Retrying in ${backoffDelay.inSeconds}s...';
      });

      Future.delayed(backoffDelay, () {
        if (mounted) {
          _fetchChartData(isRetry: true);
        }
      });
    } else {
      // Max retries reached
      setState(() {
        _chartDataPoints = null;
        _chartMinPrice = null;
        _chartMaxPrice = null;
        _chartFirstTimestamp = null;
        _chartLastTimestamp = null;
        _isLoadingChart = false;
        _chartError =
            'Failed to load chart after $_maxRetries attempts. Please try again later.';
      });
    }
  }

  Future<void> _fetchMarketStats() async {
    try {
      // For native TON, we need to use the special address
      // The API might accept the zero address or we might need a different endpoint
      final uri = Uri.parse('$_tokensApiUrl/api/v3/jettons/$_tonAddress');

      print('Fetching market stats from: $uri');
      final response = await http.get(uri);

      print('Market stats API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Market stats response: $data');

        final marketStats = data['market_stats'] as Map<String, dynamic>?;

        if (marketStats != null) {
          setState(() {
            _priceUsd = (marketStats['price_usd'] as num?)?.toDouble();
            _mcap = (marketStats['mcap'] as num?)?.toDouble();
            _fdmc = (marketStats['fdmc'] as num?)?.toDouble();
            _volume24h = (marketStats['volume_usd_24h'] as num?)?.toDouble();
            _priceChange5m =
                (marketStats['price_change_5m'] as num?)?.toDouble();
            _priceChange1h =
                (marketStats['price_change_1h'] as num?)?.toDouble();
            _priceChange6h =
                (marketStats['price_change_6h'] as num?)?.toDouble();
            _priceChange24h =
                (marketStats['price_change_24h'] as num?)?.toDouble();
          });
          print('Market stats loaded successfully');
        } else {
          print('No market_stats in response');
        }
      } else {
        print('Market stats fetch failed: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Error fetching market stats: $e');
    }
  }

  // Helper function to format numbers
  String _formatNumber(num? value, {bool isCurrency = false}) {
    if (value == null) return '...';

    if (value >= 1000000) {
      final millions = value / 1000000;
      return isCurrency
          ? '${millions.toStringAsFixed(1)}M\$'
          : '${millions.toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      final thousands = value / 1000;
      return isCurrency
          ? '${thousands.toStringAsFixed(1)}K\$'
          : '${thousands.toStringAsFixed(1)}K';
    } else {
      return isCurrency
          ? '${value.toStringAsFixed(0)}\$'
          : value.toStringAsFixed(0);
    }
  }

  // Helper function to format percentage
  String _formatPercentage(double? value) {
    if (value == null) return '...';
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  Future<void> _fetchSwapAmount() async {
    setState(() {
      _isLoadingSwapAmount = true;
      _swapAmountError = null;
    });

    try {
      // First, try to get USDT token address from API
      String usdtAddress = _usdtAddress;
      if (_usdtTokenAddress != null) {
        usdtAddress = _usdtTokenAddress!;
      } else {
        // Try to fetch USDT token from tokens list
        try {
          final tokenUri = Uri.parse('$_swapCoffeeApiUrl/v1/tokens/ton');
          final tokenResponse = await http.get(tokenUri);
          print('Token list response status: ${tokenResponse.statusCode}');
          if (tokenResponse.statusCode == 200) {
            final tokenData = jsonDecode(tokenResponse.body);
            print('Token list response: $tokenData');
            // The response might be a list or an object
            if (tokenData is List) {
              // Find USDT in the list
              for (var token in tokenData) {
                if (token is Map &&
                    (token['symbol'] as String?)?.toUpperCase() == 'USDT') {
                  final address = token['address'] as String?;
                  if (address != null) {
                    usdtAddress = address;
                    _usdtTokenAddress = address;
                    print('Found USDT address from token list: $usdtAddress');
                    break;
                  }
                }
              }
            } else if (tokenData is Map) {
              // Check if it's a single token object
              if ((tokenData['symbol'] as String?)?.toUpperCase() == 'USDT') {
                final address = tokenData['address'] as String?;
                if (address != null) {
                  usdtAddress = address;
                  _usdtTokenAddress = address;
                  print('Found USDT address from API: $usdtAddress');
                }
              }
            }
          } else {
            print('Token list fetch failed: ${tokenResponse.statusCode}');
            print('Response: ${tokenResponse.body}');
          }
        } catch (e) {
          print('Could not fetch USDT token address, using default: $e');
        }
      }

      final uri = Uri.parse('$_swapCoffeeApiUrl/v1/route/smart');

      // User wants to buy 1 TON, so we need to find how much USDT to pay
      // Input: USDT, Output: 1 TON
      final requestBody = {
        'input_token': {
          'blockchain': 'ton',
          'address': usdtAddress, // USDT token address
        },
        'output_token': {
          'blockchain': 'ton',
          'address': 'native', // TON native token
        },
        'output_amount': _buyAmount, // 1 TON (what we want to receive)
        'max_splits': 4,
      };

      print('Fetching swap amount with request: ${jsonEncode(requestBody)}');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('Swap API response status: ${response.statusCode}');
      print('Swap API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Parsed response data: $data');

        // input_amount is how much USDT we need to pay
        final inputAmount = data['input_amount'] as num?;

        if (inputAmount != null) {
          print('Found input_amount: $inputAmount');
          setState(() {
            _sellAmount = inputAmount.toDouble();
            _isLoadingSwapAmount = false;
          });
        } else {
          print(
              'No input_amount in response. Available keys: ${data.keys.toList()}');
          setState(() {
            _isLoadingSwapAmount = false;
            _swapAmountError = 'Invalid response format';
          });
        }
      } else {
        print('Swap amount fetch failed: ${response.statusCode}');
        print('Response body: ${response.body}');
        setState(() {
          _isLoadingSwapAmount = false;
          _swapAmountError = 'Failed to fetch: ${response.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      print('Error fetching swap amount: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _isLoadingSwapAmount = false;
        _swapAmountError = 'Network error';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Builder(
          builder: (context) {
            // Calculate padding statically to avoid rebuilds when keyboard opens
            // The logo visibility doesn't actually change when keyboard opens,
            // so we don't need to listen to fullscreenNotifier here
            final topPadding = GlobalLogoBar.getContentTopPadding();
            // When topPadding is 0 (TMA not fullscreen), we add a small top gap
            // inside the scrollable content so the layout matches MainPage.
            final needsScrollableTopGap = topPadding == 0.0;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onResolutionSwipeStart,
              onHorizontalDragEnd: (details) =>
                  _onResolutionSwipeEnd(details, context),
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: _getAdaptiveBottomPadding(),
                    top: topPadding),
                child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: _getGlobalBottomBarHeight() - 30),
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 15),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Column(
                                      children: [
                                      if (needsScrollableTopGap)
                                        const SizedBox(height: 10),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Always measure text width using the longest label "(Hour)" to prevent layout shifts
                                          final leftTextPainter = TextPainter(
                                            text: TextSpan(
                                              text: 'TON (Hour)', // Always use longest text for positioning
                                              style: TextStyle(
                                                fontWeight: FontWeight.w400,
                                                color: AppTheme.textColor,
                                                fontSize: 20,
                                              ),
                                            ),
                                            textDirection: TextDirection.ltr,
                                          );
                                          leftTextPainter.layout();
                                          final leftTextWidth = leftTextPainter.size.width;
                                          
                                          // Measure price text width
                                          final priceText = _effectiveTonPriceUsd != null
                                              ? '${_formatPrice(_effectiveTonPriceUsd!)}\$'
                                              : '...\$';
                                          final priceTextPainter = TextPainter(
                                            text: TextSpan(
                                              text: priceText,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w400,
                                                color: AppTheme.textColor,
                                                fontSize: 20,
                                              ),
                                            ),
                                            textDirection: TextDirection.ltr,
                                          );
                                          priceTextPainter.layout();
                                          final priceTextWidth = priceTextPainter.size.width;
                                          
                                          // Approximate selector width: 4 buttons * 30px + spacing = ~130px
                                          const selectorWidth = 130.0;
                                          const leftPadding = 5.0;
                                          
                                          // Check if centered selector would overlap text
                                          final centerX = constraints.maxWidth / 2;
                                          final selectorLeftEdge = centerX - selectorWidth / 2;
                                          final leftTextRightEdge = leftTextWidth;
                                          
                                          final shouldCenter = selectorLeftEdge >= leftTextRightEdge + leftPadding;
                                          
                                          // Calculate center position between left text and price text
                                          final availableSpace = constraints.maxWidth - leftTextWidth - priceTextWidth;
                                          final spaceCenter = leftTextWidth + availableSpace / 2;
                                          
                                          return Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('TON ${_getResolutionLabel()}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w400,
                                                        color: AppTheme.textColor,
                                                        fontSize: 20,
                                                      )),
                                                  const SizedBox.shrink(),
                                                  Text(
                                                    priceText,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w400,
                                                      color: AppTheme.textColor,
                                                      fontSize: 20,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              shouldCenter
                                                  ? Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          _buildResolutionButton('d'),
                                                          _buildResolutionButton('h'),
                                                          _buildResolutionButton('q'),
                                                          _buildResolutionButton('m'),
                                                        ],
                                                      ),
                                                    )
                                                  : Positioned(
                                                      left: spaceCenter - selectorWidth / 2,
                                                      child: Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            _buildResolutionButton('d'),
                                                            _buildResolutionButton('h'),
                                                            _buildResolutionButton('q'),
                                                            _buildResolutionButton('m'),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 15),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                'MCAP',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatNumber(_mcap,
                                                    isCurrency: true),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                'FDMC',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatNumber(_fdmc,
                                                    isCurrency: true),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                'VOL',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatNumber(_volume24h,
                                                    isCurrency: true),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                '5M',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatPercentage(
                                                    _priceChange5m),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                '1H',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatPercentage(
                                                    _priceChange1h),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                '6H',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatPercentage(
                                                    _priceChange6h),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                '24H',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w400,
                                                  color: AppTheme.textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                _formatPercentage(
                                                    _priceChange24h),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w300,
                                                  color: Color(0xFF818181),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 15),
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: _isLoadingChart
                                                          ? const Center(
                                                              child: SizedBox(
                                                                width: 20,
                                                                height: 20,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  valueColor:
                                                                      AlwaysStoppedAnimation<
                                                                          Color>(
                                                                    Color(
                                                                        0xFF818181),
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          : (_chartDataPoints !=
                                                                      null &&
                                                                  _chartDataPoints!
                                                                      .isNotEmpty)
                                                              ? LayoutBuilder(
                                                                  builder: (context,
                                                                      constraints) {
                                                                    final chartSize =
                                                                        Size(
                                                                      constraints.maxWidth.isFinite &&
                                                                              constraints.maxWidth >
                                                                                  0
                                                                          ? constraints
                                                                              .maxWidth
                                                                          : 100.0,
                                                                      constraints.maxHeight.isFinite &&
                                                                              constraints.maxHeight >
                                                                                  0
                                                                          ? constraints
                                                                              .maxHeight
                                                                          : 100.0,
                                                                    );

                                                                    return MouseRegion(
                                                                      onHover:
                                                                          (event) {
                                                                        _handleChartPointer(
                                                                            event.localPosition,
                                                                            chartSize);
                                                                      },
                                                                      onExit:
                                                                          (event) {
                                                                        setState(
                                                                            () {
                                                                          _selectedPointIndex =
                                                                              null;
                                                                        });
                                                                      },
                                                                      child:
                                                                          GestureDetector(
                                                                        onPanUpdate:
                                                                            (details) {
                                                                          _handleChartPointer(
                                                                              details.localPosition,
                                                                              chartSize);
                                                                        },
                                                                        onPanEnd:
                                                                            (details) {
                                                                          setState(
                                                                              () {
                                                                            _selectedPointIndex =
                                                                                null;
                                                                          });
                                                                        },
                                                                        onPanCancel:
                                                                            () {
                                                                          setState(
                                                                              () {
                                                                            _selectedPointIndex =
                                                                                null;
                                                                          });
                                                                        },
                                                                        child:
                                                                            SizedBox.expand(
                                                                          child: CustomPaint(
                                                                            painter:
                                                                                DiagonalLinePainter(
                                                                              dataPoints:
                                                                                  _chartDataPoints,
                                                                              selectedPointIndex:
                                                                                  _selectedPointIndex,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    );
                                                                  },
                                                                )
                                                              : Container(
                                                                  // Transparent container to maintain layout
                                                                  color: Colors
                                                                      .transparent,
                                                                  child: _chartError !=
                                                                          null
                                                                      ? Center(
                                                                          child:
                                                                              Padding(
                                                                            padding:
                                                                                const EdgeInsets.all(8.0),
                                                                            child:
                                                                                Text(
                                                                              _chartError!,
                                                                              style: const TextStyle(
                                                                                fontSize: 10,
                                                                                color: Color(0xFF818181),
                                                                              ),
                                                                              textAlign: TextAlign.center,
                                                                            ),
                                                                          ),
                                                                        )
                                                                      : null,
                                                                ),
                                                  ),
                                                  const SizedBox(height: 5.0),
                                                  SizedBox(
                                                    height:
                                                        15.0, // Fixed height to prevent layout shift
                                                    child: _selectedPointIndex != null &&
                                                            _originalChartData !=
                                                                null &&
                                                            _selectedPointIndex! <
                                                                _originalChartData!
                                                                    .length
                                                        ? _buildSelectedPointTimestampRow()
                                                        : Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              _buildTimestampWidget(
                                                                  _chartFirstTimestamp),
                                                              _buildTimestampWidget(
                                                                  _chartLastTimestamp),
                                                            ],
                                                          ),
                                                  )
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            // Price column: height = chart space (from max point to min point), top-aligned
                                            // The chart is in an Expanded Column, so we use LayoutBuilder
                                            // to get the actual chart height
                                            LayoutBuilder(
                                              builder:
                                                  (context, rowConstraints) {
                                                // The Row contains: Expanded Column + SizedBox(width: 5) + price column
                                                // The Column contains: Expanded (chart) + SizedBox(5px) + SizedBox(15px timestamps)
                                                // Chart space = Expanded widget height = Row height - 5px (spacing) - 15px (timestamps)
                                                // Price column height = chart space (full height from max to min point)
                                                final chartSpaceHeight =
                                                    rowConstraints.maxHeight -
                                                        5.0 -
                                                        15.0;

                                                return SizedBox(
                                                  width:
                                                      _calculateMaxPriceWidth(),
                                                  height: chartSpaceHeight,
                                                  child: _selectedPointIndex != null &&
                                                          _originalChartData !=
                                                              null &&
                                                          _selectedPointIndex! <
                                                              _originalChartData!
                                                                  .length
                                                      ? _buildSelectedPointPriceColumn()
                                                      : _buildNormalPriceColumn(),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.only(
                                  top: 20, bottom: 0, left: 15, right: 15),
                              child: Column(children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text('Buy',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w400,
                                          color: AppTheme.textColor,
                                          fontSize: 20,
                                        )),
                                    SizedBox(
                                      height: 20,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            Image.asset('assets/sample/1.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/2.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/3.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/4.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/5.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                        _buyAmount
                                            .toStringAsFixed(6)
                                            .replaceAll(RegExp(r'0+$'), '')
                                            .replaceAll(RegExp(r'\.$'), ''),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 20,
                                          color: AppTheme.textColor,
                                        )),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Image.asset('assets/sample/ton.png',
                                            width: 20,
                                            height: 20,
                                            fit: BoxFit.contain),
                                        const SizedBox(width: 8),
                                        Text(_buyCurrency.toLowerCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textColor,
                                              fontSize: 20,
                                            )),
                                        const SizedBox(width: 8),
                                        SvgPicture.asset(
                                          AppTheme.isLightTheme
                                              ? 'assets/icons/select_light.svg'
                                              : 'assets/icons/select_dark.svg',
                                          width: 5,
                                          height: 10,
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          _effectiveTonPriceUsd != null
                                              ? '${_formatPrice(_effectiveTonPriceUsd!)}\$'
                                              : '…',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w400,
                                            fontSize: 15,
                                            color: Color(0xFF818181),
                                          )),
                                      const Text('TON',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w400,
                                            fontSize: 15,
                                            color: Color(0xFF818181),
                                          )),
                                    ]),
                              ]),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 15),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'max.',
                                    style: TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 1.0,
                                    ),
                                    textHeightBehavior:
                                        TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                  SvgPicture.asset(
                                    AppTheme.isLightTheme
                                        ? 'assets/icons/rotate_light.svg'
                                        : 'assets/icons/rotate_dark.svg',
                                    width: 20,
                                    height: 20,
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder: (context, animation, secondaryAnimation) =>
                                              const WalletsPage(),
                                          transitionDuration: Duration.zero,
                                          reverseTransitionDuration: Duration.zero,
                                        ),
                                      );
                                      AppHaptic.heavy();
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'Sendal Rodriges',
                                          style: TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            color: Color(0xFF818181),
                                            height: 1.0,
                                          ),
                                          textHeightBehavior:
                                              TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          r'1$',
                                          style: TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            color: Color(0xFF818181),
                                            height: 1.0,
                                          ),
                                          textHeightBehavior:
                                              TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        SvgPicture.asset('assets/icons/select.svg', width: 5, height: 10),
                                      ],
                                    ),
                                  ).pointer,
                                ],
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.only(
                                  top: 15, bottom: 15, left: 15, right: 15),
                              child: Column(children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text('Sell',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w400,
                                          color: AppTheme.textColor,
                                          fontSize: 20,
                                        )),
                                    SizedBox(
                                      height: 20,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            Image.asset('assets/sample/1.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/2.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/3.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/4.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                            const SizedBox(width: 5),
                                            Image.asset('assets/sample/5.png',
                                                width: 20,
                                                height: 20,
                                                fit: BoxFit.contain),
                                          ],
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                        _isLoadingSwapAmount
                                            ? '...'
                                            : (_swapAmountError != null
                                                ? 'Error'
                                                : (_sellAmount != null
                                                    ? _sellAmount!
                                                        .toStringAsFixed(6)
                                                        .replaceAll(
                                                            RegExp(r'0+$'), '')
                                                        .replaceAll(
                                                            RegExp(r'\.$'), '')
                                                    : '1')),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 20,
                                          color: AppTheme.textColor,
                                        )),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SvgPicture.asset(
                                          'assets/sample/DLLR.svg',
                                          width: 20,
                                          height: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(_sellCurrency.toLowerCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textColor,
                                              fontSize: 20,
                                            )),
                                        const SizedBox(width: 8),
                                        SvgPicture.asset(
                                          AppTheme.isLightTheme
                                              ? 'assets/icons/select_light.svg'
                                              : 'assets/icons/select_dark.svg',
                                          width: 5,
                                          height: 10,
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          _sellAmount != null
                                              ? '${_formatPrice(_sellAmount!)}\$'
                                              : '…',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w400,
                                            fontSize: 15,
                                            color: Color(0xFF818181),
                                          )),
                                      const Text('TON',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w400,
                                            fontSize: 15,
                                            color: Color(0xFF818181),
                                          )),
                                    ]),
                              ]),
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  bottom: 10, right: 15, left: 15),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 15),
                              decoration: BoxDecoration(
                                color: const Color(0xFF818181),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Center(
                                    child: Text(
                                      'Insufficient amount',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFAFAFA),
                                        fontSize: 15,
                                        height: 20 / 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
            );
          },
        ),
        ),
    );
  }
}
