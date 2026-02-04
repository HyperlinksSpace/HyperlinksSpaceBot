import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../utils/keyboard_height_service.dart';
import '../../utils/telegram_back_button.dart';
import '../../telegram_webapp.dart';
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
    "What is my all wallet's last month profit",
    "Advise me a token to buy",
  ];

  // Store the callback reference for cleanup
  Function()? _backButtonCallback;
  bool _isFocused = false;
  bool _backButtonSetup = false;

  @override
  void initState() {
    super.initState();
    // Track initial focus state
    _isFocused = GlobalBottomBar.focusNotifier.value;
    // Listen to focus changes to update state and setup/teardown back button
    GlobalBottomBar.focusNotifier.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final newFocusState = GlobalBottomBar.focusNotifier.value;
    
    // Only react to actual changes - prevent unnecessary rebuilds
    if (newFocusState == _isFocused) return;
    
    // Update state immediately - don't delay with post-frame callback
    // Delaying causes flash because overlay appears, then state updates later
    setState(() {
      _isFocused = newFocusState;
    });
    
    if (_isFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GlobalBottomBar.focusNotifier.value && !_backButtonSetup) {
          _setupBackButton();
        }
      });
    } else {
      _teardownBackButton();
    }
  }
  
  void _setupBackButton() {
    if (_backButtonSetup) return; // Prevent multiple setups
    
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram) {
      // Create callback to unfocus input when back button is clicked
      _backButtonCallback = () {
        GlobalBottomBar.unfocusInput();
      };
      
      // Show back button and handle clicks
      // Use postFrameCallback to ensure this happens after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GlobalBottomBar.focusNotifier.value && !_backButtonSetup) {
          try {
            TelegramBackButton.show();
            TelegramBackButton.onClick(_backButtonCallback!);
            _backButtonSetup = true;
          } catch (e) {
            // Silently fail if back button setup fails
            print('Failed to setup back button: $e');
          }
        }
      });
    }
  }

  void _teardownBackButton() {
    if (!_backButtonSetup) return; // Nothing to teardown
    
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram && _backButtonCallback != null) {
      try {
        TelegramBackButton.offClick(_backButtonCallback!);
        TelegramBackButton.hide();
      } catch (e) {
        // Silently fail if back button teardown fails
        print('Failed to teardown back button: $e');
      }
      _backButtonCallback = null;
      _backButtonSetup = false;
    }
  }

  @override
  void dispose() {
    GlobalBottomBar.focusNotifier.removeListener(_onFocusChanged);
    // Clean up back button if still active
    _teardownBackButton();
    super.dispose();
  }

  void _onOptionTap(String option) {
    // Set the option text to the input field
    GlobalBottomBar.setInputText(option);
    // Keep focus so user can edit if needed
    // Don't unfocus here - let user decide when to submit
  }

  void _onOverlayTap() {
    // Close overlay when tapping outside options
    GlobalBottomBar.unfocusInput();
  }

  @override
  Widget build(BuildContext context) {
    // Use both MediaQuery and KeyboardHeightService - overlay rebuilds when either changes
    final mediaQueryKeyboard = MediaQuery.of(context).viewInsets.bottom;

    // Overlay is visible only when focused
    return Offstage(
      offstage: !_isFocused,
      child: IgnorePointer(
        ignoring: !_isFocused,
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
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            child: GestureDetector(
                              onTap: () {},
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ..._premadeOptions.map((option) => Padding(
                                        padding: const EdgeInsets.only(bottom: 20),
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
