import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../../app/theme/app_theme.dart';
import '../../utils/keyboard_height_service.dart';
import '../../utils/app_haptic.dart';
import '../../widgets/global/global_bottom_bar.dart';
import '../common/edge_swipe_back.dart';

/// Overlay widget that appears when AI & Search input is focused
/// Shows premade input options and overlays page content
class AiSearchOverlay extends StatefulWidget {
  const AiSearchOverlay({super.key});

  @override
  State<AiSearchOverlay> createState() => _AiSearchOverlayState();
}

class _AiSearchOverlayState extends State<AiSearchOverlay> {
  // Premade input options
  final List<String> _premadeOptions = [
    "What is the universe?",
    "Tell me about dogs token",
  ];

  StreamSubscription<tma.BackButton>? _backButtonSubscription;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = GlobalBottomBar.focusNotifier.value;
    GlobalBottomBar.focusNotifier.addListener(_updateBackButtonState);
    GlobalBottomBar.isAiPageOpenNotifier.addListener(_updateBackButtonState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBackButtonState());
  }

  /// Centralized: single listener, never torn down during overlay↔AI page transitions.
  /// Show Back when overlay focused OR AI page open; hide only when both closed.
  void _updateBackButtonState() {
    if (!mounted) return;
    final focus = GlobalBottomBar.focusNotifier.value;
    final aiPageOpen = GlobalBottomBar.isAiPageOpen;
    final shouldShowBack = focus || aiPageOpen;
    setState(() => _isFocused = focus);
    if (shouldShowBack) {
      _ensureBackButtonActive();
    } else {
      // Delay teardown so we don't hide when transitioning AI page → overlay (focus not yet set)
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        if (GlobalBottomBar.focusNotifier.value || GlobalBottomBar.isAiPageOpen) return;
        _teardownBackButton();
      });
    }
  }

  void _ensureBackButtonActive() {
    if (_backButtonSubscription != null) return;
    try {
      final webApp = tma.WebApp();
      _backButtonSubscription = webApp.eventHandler.backButtonClicked.listen((_) {
        if (GlobalBottomBar.isAiPageOpen) {
          GlobalBottomBar.popAiPageIfOpen();
        } else if (GlobalBottomBar.focusNotifier.value) {
          GlobalBottomBar.unfocusInput();
        }
      });
      webApp.backButton.show();
    } catch (e) {
      print('Failed to setup back button: $e');
    }
  }

  void _teardownBackButton() {
    if (_backButtonSubscription == null) return;
    _backButtonSubscription?.cancel();
    _backButtonSubscription = null;
    try {
      tma.WebApp().backButton.hide();
    } catch (_) {}
  }

  @override
  void dispose() {
    GlobalBottomBar.focusNotifier.removeListener(_updateBackButtonState);
    GlobalBottomBar.isAiPageOpenNotifier.removeListener(_updateBackButtonState);
    _teardownBackButton();
    super.dispose();
  }

  void _onOptionTap(String option) {
    AppHaptic.heavy();
    // Set option and immediately submit without closing focus first.
    GlobalBottomBar.setInputText(option);
    GlobalBottomBar.submitCurrentInput();
  }

  void _onOverlayTap() {
    AppHaptic.heavy();
    // Close overlay when tapping outside options
    GlobalBottomBar.unfocusInput();
  }

  @override
  Widget build(BuildContext context) {
    // Use both MediaQuery and KeyboardHeightService - overlay rebuilds when either changes
    final mediaQueryKeyboard = MediaQuery.of(context).viewInsets.bottom;
    final shouldHideOverlay = !_isFocused || GlobalBottomBar.isAiPageOpen;

    // Overlay is visible only when focused
    return Offstage(
      offstage: shouldHideOverlay,
      child: IgnorePointer(
        ignoring: shouldHideOverlay,
        child: EdgeSwipeBack(
          onBack: _onOverlayTap,
          child: GestureDetector(
            onTap: _onOverlayTap,
            behavior: HitTestBehavior.translucent,
            child: Material(
              color: AppTheme.backgroundColor,
              child: SizedBox.expand(
                child: ValueListenableBuilder<double>(
                  valueListenable: KeyboardHeightService().heightNotifier,
                  builder: (context, serviceKeyboard, _) {
                    final keyboardBottom =
                        math.max(mediaQueryKeyboard, serviceKeyboard);
                    return Padding(
                      padding: EdgeInsets.only(bottom: keyboardBottom),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          const Spacer(flex: 1),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              child: GestureDetector(
                                onTap: () {},
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    ..._premadeOptions.map((option) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 20),
                                          child: GestureDetector(
                                            onTap: () => _onOptionTap(option),
                                            behavior: HitTestBehavior.opaque,
                                            child: Text(
                                              option,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Aeroport',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: AppTheme.textColor,
                                              ),
                                            ),
                                          ),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(flex: 1),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
