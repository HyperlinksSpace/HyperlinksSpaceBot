import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../widgets/global/global_logo_bar.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../telegram_safe_area.dart';
import '../app/theme/app_theme.dart';
import '../telegram_webapp.dart';
import '../utils/app_haptic.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  StreamSubscription<tma.BackButton>? _backButtonSubscription;

  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();
    return safeAreaInset.bottom + 59;
  }

  void _updateScrollIndicator() {
    if (_scrollController.hasClients) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicator);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicator();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final webApp = tma.WebApp();
        final eventHandler = webApp.eventHandler;
        _backButtonSubscription =
            eventHandler.backButtonClicked.listen((_) => _handleBackButton());
        try {
          TelegramWebApp().onBackButtonClick(_handleBackButton);
        } catch (_) {}
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) webApp.backButton.show();
        });
      } catch (_) {}
    });
    // Hide loading once content is ready (assets are in bundle; brief delay for consistency with other pages)
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _backButtonSubscription?.cancel();
    try {
      tma.WebApp().backButton.hide();
    } catch (_) {}
    super.dispose();
  }

  static const List<String> _imageAssets = [
    'assets/Apps/1.svg',
    'assets/Apps/2.svg',
    'assets/Apps/3.svg',
  ];

  static const double _gapBetween = 15;

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    // Match MainPage: add internal top gap when not fullscreen.
    final needsScrollableTopGap = topPadding == 0.0;
    final bottomPadding = _getAdaptiveBottomPadding();
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Content width: full width minus horizontal padding, capped at 570
    final contentWidth =
        (screenWidth - 30).clamp(0.0, 570.0);
    // Strict square: height = width for each image slot
    final slotSize = contentWidth;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: topPadding,
                left: 15,
                right: 15,
                bottom: bottomPadding,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 570),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (needsScrollableTopGap)
                          const SizedBox(height: 10),
                        for (int i = 0; i < _imageAssets.length; i++) ...[
                          if (i > 0) const SizedBox(height: _gapBetween),
                          SizedBox(
                            height: slotSize,
                            width: double.infinity,
                            child: SvgPicture.asset(
                              _imageAssets[i],
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Scroll indicator (same as trade page)
            Positioned(
              right: 5,
              top: topPadding,
              bottom: bottomPadding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final containerHeight = constraints.maxHeight;
                  if (containerHeight <= 0 ||
                      !_scrollController.hasClients) {
                    return const SizedBox.shrink();
                  }
                  try {
                    final position = _scrollController.position;
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
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: AppTheme.backgroundColor,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF818181),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
