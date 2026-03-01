import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../telegram_safe_area.dart';
import '../utils/app_haptic.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/global/global_logo_bar.dart';

/// Example page with logo bar, bottom bar, back, scrolling, and scroll indicator (same as trade page).
class APageExample extends StatefulWidget {
  const APageExample({super.key});

  @override
  State<APageExample> createState() => _APageExampleState();
}

class _APageExampleState extends State<APageExample> {
  final ScrollController _mainScrollController = ScrollController();

  double _getAdaptiveBottomPadding() {
    final safeAreaInset = TelegramSafeAreaService().getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  void _updateScrollIndicator() {
    if (_mainScrollController.hasClients) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _mainScrollController.addListener(_updateScrollIndicator);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicator();
    });
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    // Match MainPage: add internal gap when not fullscreen.
    final needsScrollableTopGap = topPadding == 0.0;
    final bottomPadding = _getAdaptiveBottomPadding();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: () {
          AppHaptic.heavy();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        child: Builder(
          builder: (context) {
            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: SingleChildScrollView(
                        controller: _mainScrollController,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(
                            top: 15,
                            bottom: 15,
                            left: 15,
                            right: 15,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (needsScrollableTopGap)
                                const SizedBox(height: 10),
                              Text(
                                'A Page Example',
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 30,
                                  height: 1.0,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.textColor,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'This page has logo bar, bottom bar, back, and scrolling '
                                'functionality like the trade page.',
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.textColor,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ...List.generate(64, (i) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'Scrollable line ${i + 1}',
                                    style: const TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 1.2,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Scroll indicator - same as trade page
                Positioned(
                  right: 5,
                  top: topPadding,
                  bottom: bottomPadding,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final containerHeight = constraints.maxHeight;
                      if (containerHeight <= 0 ||
                          !_mainScrollController.hasClients) {
                        return const SizedBox.shrink();
                      }

                      try {
                        final position = _mainScrollController.position;
                        final maxScroll = position.maxScrollExtent;
                        final currentScroll = position.pixels;
                        final viewportHeight = position.viewportDimension;
                        final totalHeight = viewportHeight + maxScroll;

                        if (maxScroll <= 0 || totalHeight <= 0) {
                          return const SizedBox.shrink();
                        }

                        final indicatorHeightRatio =
                            (viewportHeight / totalHeight).clamp(0.0, 1.0);
                        final indicatorHeight =
                            (containerHeight * indicatorHeightRatio)
                                .clamp(0.0, containerHeight);

                        if (indicatorHeight <= 0) {
                          return const SizedBox.shrink();
                        }

                        final scrollPosition =
                            (currentScroll / maxScroll).clamp(0.0, 1.0);
                        final availableSpace = (containerHeight - indicatorHeight)
                            .clamp(0.0, containerHeight);
                        final topPosition = (scrollPosition * availableSpace)
                            .clamp(0.0, containerHeight);

                        return Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(top: topPosition),
                            child: Container(
                              width: 1,
                              height: indicatorHeight,
                              color: const Color(0xFF818181),
                            ),
                          ),
                        );
                      } catch (_) {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
