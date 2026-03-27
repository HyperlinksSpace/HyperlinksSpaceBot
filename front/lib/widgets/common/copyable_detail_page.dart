import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../../app/theme/app_theme.dart';
import '../../widgets/global/global_logo_bar.dart';
import '../../widgets/common/edge_swipe_back.dart';
import '../../widgets/common/pointer_region.dart';
import '../../app/app.dart';
import '../../telegram_safe_area.dart';
import '../../utils/app_haptic.dart';

/// Reusable full-page layout: header row, centered content. Tap/click copies [copyText] (newlines stripped); "Copied!" appears for 1 second then disappears. No clipboard read.
class CopyableDetailPage extends StatefulWidget {
  /// Raw text to copy (newlines removed when copying).
  final String copyText;

  /// Center content (plain text). Whole area is tappable for copy/clear.
  final Widget Function() centerChildBuilder;

  /// Left header label (e.g. '..xk5str4e').
  final String titleLeft;

  /// Right header label (e.g. 'Sendal Rodriges').
  final String titleRight;

  /// When set, the title right row is tappable and calls this (e.g. navigate to WalletsPage).
  final VoidCallback? onTitleRightTap;

  const CopyableDetailPage({
    super.key,
    required this.copyText,
    required this.centerChildBuilder,
    this.titleLeft = '..xk5str4e',
    this.titleRight = 'Sendal Rodriges',
    this.onTitleRightTap,
  });

  @override
  State<CopyableDetailPage> createState() => _CopyableDetailPageState();
}

class _CopyableDetailPageState extends State<CopyableDetailPage>
    with RouteAware {
  StreamSubscription<tma.BackButton>? _backButtonSubscription;
  bool _showCopiedIndicator = false;
  bool _routeObserverSubscribed = false;
  Timer? _copiedHideTimer;

  static double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  static double _getGlobalBottomBarHeight() {
    return 10.0 + 30.0 + 15.0;
  }

  String get _oneLine => widget.copyText.replaceAll('\n', '');

  void _onTap() {
    _copiedHideTimer?.cancel();
    Clipboard.setData(ClipboardData(text: _oneLine));
    AppHaptic.heavy();
    if (mounted) setState(() => _showCopiedIndicator = true);
    _copiedHideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showCopiedIndicator = false);
    });
  }

  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final webApp = tma.WebApp();
        final eventHandler = webApp.eventHandler;
        _backButtonSubscription =
            eventHandler.backButtonClicked.listen((_) => _handleBackButton());
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) tma.WebApp().backButton.show();
        });
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route != null && route is PageRoute) {
      MyApp.routeObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  @override
  void dispose() {
    _copiedHideTimer?.cancel();
    if (_routeObserverSubscribed) {
      MyApp.routeObserver.unsubscribe(this);
    }
    _backButtonSubscription?.cancel();
    try {
      tma.WebApp().backButton.hide();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    // Match MainPage: no external top gap when not fullscreen; internal layout already
    // reserves 30px header height, so we only need the scrollbar to start flush.
    final bottomBarHeight = _getGlobalBottomBarHeight();

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
                bottom: _getAdaptiveBottomPadding() + bottomBarHeight,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 570),
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: topPadding == 0.0 ? 10.0 : 0.0),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SizedBox(
                            height: 30,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Center(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    widget.titleLeft,
                                    style: const TextStyle(
                                      fontFamily: 'Aeroport Mono',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 2.0,
                                    ),
                                    textHeightBehavior:
                                        const TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                ),
                              ),
                              widget.onTitleRightTap != null
                                  ? GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        FocusManager.instance.primaryFocus?.unfocus();
                                        widget.onTitleRightTap!();
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            widget.titleRight,
                                            style: const TextStyle(
                                              fontFamily: 'Aeroport',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w400,
                                              color: Color(0xFF818181),
                                              height: 2.0,
                                            ),
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          SvgPicture.asset(
                                            'assets/icons/select.svg',
                                            width: 5,
                                            height: 10,
                                          ),
                                        ],
                                      ),
                                    ).pointer
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          widget.titleRight,
                                          style: const TextStyle(
                                            fontFamily: 'Aeroport',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            color: Color(0xFF818181),
                                            height: 2.0,
                                          ),
                                          textHeightBehavior:
                                              const TextHeightBehavior(
                                            applyHeightToFirstAscent: false,
                                            applyHeightToLastDescent: false,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        SvgPicture.asset(
                                          'assets/icons/select.svg',
                                          width: 5,
                                          height: 10,
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _onTap,
                                child: widget.centerChildBuilder(),
                              ).pointer,
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: _onTap,
                                child: SizedBox(
                                  height: 15,
                                  child: _showCopiedIndicator
                                      ? Center(
                                          child: Text(
                                            'Copied!',
                                            key: const Key('copy_text'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              height: 15 / 15,
                                              fontWeight: FontWeight.w400,
                                              color: AppTheme.textColor,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ).pointer,
                            ],
                          ),
                        ),
                      ),
                    ],
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
