import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../widgets/global/global_logo_bar.dart';
import '../telegram_safe_area.dart';
import '../app/theme/app_theme.dart';
import '../telegram_webapp.dart';
import '../widgets/global/global_bottom_bar.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with TickerProviderStateMixin {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _isAddressFocused = false;
  
  final TextEditingController _address2Controller = TextEditingController();
  final FocusNode _address2FocusNode = FocusNode();
  bool _isAddress2Focused = false;

  // Background animation controllers
  late final AnimationController _bgController;
  late final Animation<double> _bgAnimation;
  late final AnimationController _noiseController;
  late final Animation<double> _noiseAnimation;
  late final double _bgSeed;

  void _handleBackButton() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  StreamSubscription<tma.BackButton>? _backButtonSubscription;

  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }

  @override
  void initState() {
    super.initState();

    // Initialize background animations
    final random = math.Random();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
    _bgAnimation =
        CurvedAnimation(parent: _bgController, curve: Curves.easeInOut);
    _bgSeed = random.nextDouble();
    _noiseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat(reverse: true);
    _noiseAnimation =
        Tween<double>(begin: -0.2, end: 0.2).animate(CurvedAnimation(
      parent: _noiseController,
      curve: Curves.easeInOut,
    ));

    _addressFocusNode.addListener(() {
      setState(() {
        _isAddressFocused = _addressFocusNode.hasFocus;
      });
    });

    _addressController.addListener(() {
      setState(() {});
    });

    _address2FocusNode.addListener(() {
      setState(() {
        _isAddress2Focused = _address2FocusNode.hasFocus;
      });
    });

    _address2Controller.addListener(() {
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final webApp = tma.WebApp();
        final eventHandler = webApp.eventHandler;

        _backButtonSubscription =
            eventHandler.backButtonClicked.listen((backButton) {
          print('[SendPage] Back button clicked!');
          _handleBackButton();
        });

        print('[SendPage] Back button listener registered');

        try {
          final telegramWebApp = TelegramWebApp();
          telegramWebApp.onBackButtonClick(() {
            print('[SendPage] Back button clicked (fallback)!');
            _handleBackButton();
          });
          print('[SendPage] Fallback back button listener registered');
        } catch (e) {
          print('[SendPage] Error setting up fallback back button: $e');
        }

        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            if (mounted) {
              webApp.backButton.show();
              print('[SendPage] Back button shown');
            }
          } catch (e) {
            print('[SendPage] Error showing back button: $e');
          }
        });
      } catch (e) {
        print('[SendPage] Error setting up back button: $e');
      }
    });
  }

  @override
  void dispose() {
    _backButtonSubscription?.cancel();
    _addressController.dispose();
    _addressFocusNode.dispose();
    _address2Controller.dispose();
    _address2FocusNode.dispose();
    _bgController.dispose();
    _noiseController.dispose();

    try {
      tma.WebApp().backButton.hide();
    } catch (e) {
      // Ignore errors
    }

    super.dispose();
  }

  Color _shiftColor(Color base, double shift) {
    final hsl = HSLColor.fromColor(base);
    final newLightness = (hsl.lightness + shift).clamp(0.0, 1.0);
    final newHue = (hsl.hue + shift * 10) % 360;
    final newSaturation = (hsl.saturation + shift * 0.1).clamp(0.0, 1.0);
    return hsl
        .withLightness(newLightness)
        .withHue(newHue)
        .withSaturation(newSaturation)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final bottomBarHeight = GlobalBottomBar.getBottomBarHeight(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _bgAnimation,
        builder: (context, child) {
          final baseShimmer =
              math.sin(2 * math.pi * (_bgAnimation.value + _bgSeed));
          final shimmer = 0.007 * baseShimmer;
          final baseColors = AppTheme.baseColors;
          const stopsCount = 28;
          final colors = List.generate(stopsCount, (index) {
            final progress = index / (stopsCount - 1);
            final scaled = progress * (baseColors.length - 1);
            final lowerIndex = scaled.floor();
            final upperIndex = scaled.ceil();
            final frac = scaled - lowerIndex;
            final lower =
                baseColors[lowerIndex.clamp(0, baseColors.length - 1)];
            final upper =
                baseColors[upperIndex.clamp(0, baseColors.length - 1)];
            final blended = Color.lerp(lower, upper, frac)!;
            final offset = index * 0.0015;
            return _shiftColor(blended, shimmer * (0.035 + offset));
          });
          final stops = List.generate(
              colors.length, (index) => index / (colors.length - 1));
          final rotation =
              math.sin(2 * math.pi * (_bgAnimation.value + _bgSeed)) * 0.35;
          final begin = Alignment(-0.8 + rotation, -0.7 - rotation * 0.2);
          final end = Alignment(0.9 - rotation, 0.8 + rotation * 0.2);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: colors,
                    stops: stops,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _noiseAnimation,
                builder: (context, _) {
                  final alignment = Alignment(
                    0.2 + _noiseAnimation.value,
                    -0.4 + _noiseAnimation.value * 0.5,
                  );
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: alignment,
                        radius: 0.75,
                        colors: [
                          Colors.white.withValues(alpha: 0.01),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  );
                },
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.7, -0.6),
                    radius: 0.8,
                    colors: [
                      _shiftColor(AppTheme.radialGradientColor, shimmer * 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  color: AppTheme.overlayColor.withValues(alpha: 0.02),
                ),
              ),
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.01),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.005),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              top: false,
              child: ValueListenableBuilder<bool>(
                valueListenable: GlobalLogoBar.fullscreenNotifier,
                builder: (context, isFullscreen, child) {
                  final topPadding = GlobalLogoBar.getContentTopPadding();
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: _getAdaptiveBottomPadding() + bottomBarHeight + 60, // Add space for button
                      top: topPadding,
                      left: 15,
                      right: 15,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 570),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                        // First content row with two blocks
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // First block: ..xk5str4e
                            const Text(
                              '..xk5str4e',
                              style: TextStyle(
                                fontFamily: 'Aeroport Mono',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF818181),
                              ),
                            ),
                            // Second block: Sendal Rodriges with icon
                            Row(
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
                                  textHeightBehavior: TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                SvgPicture.asset('assets/icons/select.svg', width: 5, height: 10),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Second content row with Send headline and coin block
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Send headline
                            Text(
                              'Send',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                fontSize: 20,
                              ),
                            ),
                            // Coin block with DLLR
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/sample/DLLR.svg',
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'dllr',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textColor,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SvgPicture.asset(
                                  AppTheme.isLightTheme
                                      ? 'assets/icons/select_light.svg'
                                      : 'assets/icons/select_dark.svg',
                                  width: 5,
                                  height: 10,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        // Third content row with 1 and max.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Just "1" text (same style as amount on swap page)
                            Text(
                              '1',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 20,
                                color: AppTheme.textColor,
                              ),
                            ),
                            // max. text at the right
                            Text(
                              'max.',
                              style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                height: 1.0,
                              ),
                              textHeightBehavior: TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        // Fourth content row with 1$ and having 1 dllr on ton
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 1$ text at the left
                            const Text(
                              r'$1',
                              style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF818181),
                                height: 1.0,
                              ),
                              textHeightBehavior: TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                            ),
                            // having 1 dllr on ton text at the right
                            const Text(
                              'having 1 dllr on ton',
                              style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF818181),
                                height: 1.0,
                              ),
                              textHeightBehavior: TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        // Fifth content row with Address and paste.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Address text at the left (same style as Send)
                            Text(
                              'Address',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                fontSize: 20,
                              ),
                            ),
                            // paste. text at the right (same style as max.)
                            Text(
                              'paste.',
                              style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                height: 1.0,
                              ),
                              textHeightBehavior: TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        // Sixth content row with address input
                        TextField(
                          controller: _addressController,
                          focusNode: _addressFocusNode,
                          cursorColor: AppTheme.textColor,
                          cursorHeight: 15,
                          style: TextStyle(
                            fontFamily: 'Aeroport',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 2.0,
                            color: AppTheme.textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: (_isAddressFocused || _addressController.text.isNotEmpty)
                                ? null
                                : 'Enter address',
                            hintStyle: const TextStyle(
                              fontFamily: 'Aeroport',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF818181),
                              height: 1.0,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 30),
                        // Seventh content row with Address and paste. (duplicate)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Address text at the left (same style as Send)
                            Text(
                              'Comment / Memo',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                fontSize: 20,
                              ),
                            ),
                            // paste. text at the right (same style as max.)
                            Text(
                              'paste.',
                              style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: AppTheme.textColor,
                                height: 1.0,
                              ),
                              textHeightBehavior: TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        // Eighth content row with address input (duplicate)
                        TextField(
                          controller: _address2Controller,
                          focusNode: _address2FocusNode,
                          cursorColor: AppTheme.textColor,
                          cursorHeight: 15,
                          style: TextStyle(
                            fontFamily: 'Aeroport',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 2.0,
                            color: AppTheme.textColor,
                          ),
                          decoration: InputDecoration(
                            hintText: (_isAddress2Focused || _address2Controller.text.isNotEmpty)
                                ? null
                                : 'Enter comment / memo',
                            hintStyle: const TextStyle(
                              fontFamily: 'Aeroport',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF818181),
                              height: 1.0,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
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
            // Send button positioned at the bottom, above GlobalBottomBar
            Positioned(
              bottom: keyboardHeight + bottomBarHeight,
              left: 0,
              right: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF818181),
                        borderRadius: BorderRadius.zero, // No rounded corners
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Center(
                            child: Text(
                              'Send',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white, // White text for contrast on #818181
                                fontSize: 15,
                                height: 20 / 15,
                              ),
                            ),
                          ),
                        ],
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
