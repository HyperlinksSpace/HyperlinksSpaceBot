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
import '../widgets/global/global_bottom_bar.dart';
import '../utils/keyboard_height_service.dart';
import 'wallets_page.dart';
import '../widgets/common/pointer_region.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _isAddressFocused = false;
  
  final TextEditingController _address2Controller = TextEditingController();
  final FocusNode _address2FocusNode = FocusNode();
  bool _isAddress2Focused = false;


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
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }

  @override
  void initState() {
    super.initState();

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
    

    try {
      tma.WebApp().backButton.hide();
    } catch (e) {
      // Ignore errors
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't read MediaQuery here - it causes entire page to rebuild when keyboard opens
    // Use static values and wrap only the button positioning in ValueListenableBuilder
    final bottomBarHeight = GlobalBottomBar.getBottomBarHeight(context);
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Stack(
          children: [
            Builder(
                builder: (context) {
                  // Calculate padding statically to avoid rebuilds when keyboard opens
                  // The logo visibility doesn't actually change when keyboard opens,
                  // so we don't need to listen to fullscreenNotifier here
                  final topPadding = GlobalLogoBar.getContentTopPadding();
                  // When topPadding is 0 (TMA not fullscreen), we add a small top gap
                  // inside the scrollable content so the scrollbar sticks to the top.
                  final needsScrollableTopGap = topPadding == 0.0;
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
                        if (needsScrollableTopGap)
                          const SizedBox(height: 10),
                        // First content row (30px height to match main/CopyableDetailPage title row)
                        SizedBox(
                          height: 30,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Center(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '..xk5str4e',
                                    style: TextStyle(
                                      fontFamily: 'Aeroport Mono',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 2.0,
                                    ),
                                    textHeightBehavior: TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                ),
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
                                        height: 2.0,
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
                              ).pointer,
                            ],
                          ),
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
                              r'1$',
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
          // Send button positioned at the bottom, above GlobalBottomBar
          // Wrap in ValueListenableBuilder so only this widget rebuilds when keyboard opens
          ValueListenableBuilder<double>(
            valueListenable: KeyboardHeightService().heightNotifier,
            builder: (context, keyboardHeight, child) {
              return Positioned(
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
                                'N / A',
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
              );
            },
          ),
        ],
      ),
        ),
    );
  }
}
