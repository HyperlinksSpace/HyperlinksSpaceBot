import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../app/theme/app_theme.dart';
import '../widgets/global/global_logo_bar.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../telegram_safe_area.dart';
import '../telegram_webapp.dart';
import '../utils/app_haptic.dart';

class _TradeFeedItem extends StatelessWidget {
  const _TradeFeedItem({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          item['icon'] as String,
          width: 40,
          height: 40,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item['primaryText'] as String,
                    style: TextStyle(
                      fontFamily: 'Aeroport',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textColor,
                      height: 1.0,
                    ),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item['secondaryText'] as String,
                    style: const TextStyle(
                      fontFamily: 'Aeroport',
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF818181),
                      height: 1.0,
                    ),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              height: 20,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  item['timestamp'] as String,
                  style: TextStyle(
                    fontFamily: 'Aeroport',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.right,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 20,
              child: item['rightText'] != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        item['rightText'] as String,
                        style: const TextStyle(
                          fontFamily: 'Aeroport',
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF818181),
                          height: 1.0,
                        ),
                        textAlign: TextAlign.right,
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }
}

class _TradeColumn extends StatelessWidget {
  const _TradeColumn({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  final String imagePath;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: AspectRatio(
            aspectRatio: 1,
            child: SvgPicture.asset(
              imagePath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF818181),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  // Trade feed items (40x40 preview, same structure as main page feed)
  List<Map<String, dynamic>> get _tradeFeedItems => [
        {
          'icon': 'assets/sample/items/1.svg',
          'primaryText': 'Some walley',
          'secondaryText': r'777$',
          'timestamp': '1',
          'rightText': r'10,123$',
        },
        {
          'icon': 'assets/sample/items/2.svg',
          'primaryText': 'Sty. ker',
          'secondaryText': r'537$',
          'timestamp': '2',
          'rightText': r'9,9999$',
        },
        {
          'icon': 'assets/sample/items/3.svg',
          'primaryText': '4iza',
          'secondaryText': r'157$',
          'timestamp': '3',
          'rightText': r'7111$',
        },
      ];

  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  
  StreamSubscription<tma.BackButton>? _backButtonSubscription;

  // Scroll controller for main content
  final ScrollController _mainScrollController = ScrollController();

  // Helper method to calculate adaptive bottom padding
  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();

    // Formula: bottom SafeAreaInset + 30px
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }


  // Update scroll indicator state
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
    _mainScrollController.dispose();
    _backButtonSubscription?.cancel();

    // Hide back button when leaving trade page
    try {
      tma.WebApp().backButton.hide();
    } catch (e) {
      // Ignore errors
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Builder(
          builder: (context) {
            final topPadding = GlobalLogoBar.getContentTopPadding();
            // When topPadding is 0 (TMA not fullscreen), we add a small top gap
            // inside the scrollable content so the scrollbar sticks to the
            // top edge of the viewport, matching MainPage behavior.
            final needsScrollableTopGap = topPadding == 0.0;
            final bottomPadding = _getAdaptiveBottomPadding();
            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                      bottom: bottomPadding,
                      top: topPadding),
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
                    // First block: 2 columns with pictures, titles, subtitles
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TradeColumn(
                            imagePath: 'assets/sample/pixakats.svg',
                            title: 'pixa kats',
                            subtitle: 'Tandam',
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _TradeColumn(
                            imagePath: 'assets/sample/Haramarta.svg',
                            title: 'Haramarta',
                            subtitle: 'Bid Raits',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // Second block: three 11×11 squares (centered)
                    SizedBox(
                      height: 11,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          Container(
                            width: 11,
                            height: 11,
                            color: AppTheme.textColor,
                          ),
                        const SizedBox(width: 11),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF818181),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF818181),
                              width: 1,
                            ),
                          ),
                        ),
                          ],
                        ),
                      ),
                    ),
                    // 33px visual gap; text line height 83/20 adds ~31px above glyphs, so use 2px
                    const SizedBox(height: 33),
                    // Third block: two texts
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tranding',
                          style: TextStyle(
                            fontSize: 20,
                            height: 15 / 20,
                            color: AppTheme.textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Text(
                          'Cap',
                          style: TextStyle(
                            fontSize: 20,
                            height: 15 / 20,
                            color: const Color(0xFF818181),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Text(
                          'Reach',
                          style: TextStyle(
                            fontSize: 20,
                            height: 15 / 20,
                            color: const Color(0xFF818181),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    Row(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '24h',
                              style: TextStyle(
                                fontSize: 15,
                                height: 21 / 15,
                                color: AppTheme.textColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            SvgPicture.asset(
                              'assets/icons/ap.svg',
                              width: 11,
                              height: 11,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        const SizedBox(width: 13),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Any chain',
                              style: TextStyle(
                                fontSize: 15,
                                height: 21 / 15,
                                color: AppTheme.textColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            SvgPicture.asset(
                              'assets/icons/ap.svg',
                              width: 11,
                              height: 11,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'COLLECTION / FLOOR',
                          style: TextStyle(
                            fontSize: 11,
                            height: 21 / 11,
                            color: const Color(0xFF818181),
                          ),
                        ),
                        Text(
                          'PLACE / VOL',
                          style: TextStyle(
                            fontSize: 11,
                            height: 21 / 11,
                            color: const Color(0xFF818181),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // Feed-style blocks (same as main page, 40x40 preview)
                    ..._tradeFeedItems.asMap().entries.expand((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return [
                        if (index > 0) const SizedBox(height: 22),
                        _TradeFeedItem(item: item),
                      ];
                    }),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
                // Scroll indicator - same as main page
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
                      } catch (e) {
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
