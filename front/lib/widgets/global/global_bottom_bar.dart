import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/theme/app_theme.dart';
import '../common/pointer_region.dart';
import '../../app/app.dart';
import '../../pages/ai_page.dart';
import '../../utils/app_haptic.dart';
// TODO: AI functionality will be rebuilt from scratch
// import '../../pages/new_page.dart';
// import '../../analytics.dart';

// Global bottom bar widget that appears on all pages
class GlobalBottomBar extends StatefulWidget {
  const GlobalBottomBar({super.key});

  /// Total height of the bottom bar in logical pixels.
  static const double barHeight = 59.0;

  @override
  State<GlobalBottomBar> createState() => _GlobalBottomBarState();

  // Static notifier to track focus state across the app
  static final ValueNotifier<bool> _focusNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<bool> get focusNotifier => _focusNotifier;

  // Track whether the AI page is currently visible
  static bool get isAiPageOpen => _GlobalBottomBarState._isAiPageOpen;
  static final ValueNotifier<bool> isAiPageOpenNotifier = ValueNotifier<bool>(false);
  static void setAiPageOpen(bool isOpen) {
    _GlobalBottomBarState._isAiPageOpen = isOpen;
    isAiPageOpenNotifier.value = isOpen;
  }

  // Static method to unfocus the input (can be called from anywhere)
  static void unfocusInput() {
    _focusNotifier.value = false;
    // The actual unfocus will be handled by the state
  }

  // Request focus on the AI & Search input (e.g. when returning from AI page so overlay is shown)
  static VoidCallback? _requestFocusCallback;
  static void requestInputFocus() {
    _requestFocusCallback?.call();
  }

  /// Pop the AI page if it's on top (for centralized back button handler)
  static void popAiPageIfOpen() {
    if (!isAiPageOpen) return;
    MyApp.navigatorKey.currentState?.pop(true);
  }

  // Static reference to the controller (set by the state)
  static TextEditingController? _controllerInstance;
  static VoidCallback? _submitCurrentInputCallback;

  // Static method to set input text (can be called from anywhere)
  static void setInputText(String text) {
    if (_controllerInstance != null) {
      _controllerInstance!.text = text;
      _controllerInstance!.selection = TextSelection.collapsed(
        offset: text.length,
      );
    }
  }

  static String getInputText() {
    return _controllerInstance?.text ?? '';
  }

  // Submit current input text using the same logic as tap/enter.
  static void submitCurrentInput() {
    _submitCurrentInputCallback?.call();
  }

  /// Bottom bar height (for layout/padding so content is not overlayed).
  static double getBottomBarHeight(BuildContext? context) {
    return _GlobalBottomBarState._currentBarHeight;
  }

  /// Premade prompt options shown in overlay; when apply is pressed with empty input, a random one is used.
  static const List<String> premadePromptOptions = [
    'What is the universe?',
    'Tell me about dogs token',
  ];
}

class _GlobalBottomBarState extends State<GlobalBottomBar> {
  static bool _isAiPageOpen = false;
  static double _currentBarHeight = GlobalBottomBar.barHeight;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _inputScrollController = ScrollController();
  bool _isFocused = false;
  /// Max lines before bar stops growing; bar height capped at [_maxBarHeight].
  static const int _maxLinesBeforeScroll = 7;
  static const double _fontSize = 15.0;
  /// Line height in logical pixels (user requirement: 20px).
  static const double _lineHeightPx = 20.0;
  /// Top and bottom indent for text/placeholder (user requirement: 20px from bottom at start and on input).
  static const double _verticalPadding = 20.0;
  /// Apply icon distance from bottom (user requirement: 25px anytime).
  static const double _applyIconBottomPadding = 25.0;
  /// Bar stops extending at this height (7 lines × 20px + 20 top + 20 bottom = 180).
  static const double _maxBarHeight = 180.0;
  /// Content height when in scroll mode (180 - 40 = 140).
  static const double _scrollModeContentHeight = _maxBarHeight - 2 * _verticalPadding;

  @override
  void initState() {
    super.initState();
    // Set the static controller reference
    GlobalBottomBar._controllerInstance = _controller;
    GlobalBottomBar._submitCurrentInputCallback = _navigateToNewPage;
    GlobalBottomBar._requestFocusCallback = () {
      if (_focusNode.canRequestFocus) _focusNode.requestFocus();
    };

    _focusNode.addListener(() {
      final newFocusState = _focusNode.hasFocus;
      setState(() {
        _isFocused = newFocusState;
      });
      GlobalBottomBar._focusNotifier.value = newFocusState;
      if (newFocusState) AppHaptic.heavy();
    });

    // Listen to global unfocus requests
    GlobalBottomBar._focusNotifier.addListener(_onGlobalFocusChange);
    _controller.addListener(_onInputTextChanged);
    _inputScrollController.addListener(_onInputScrollChanged);
  }

  void _onGlobalFocusChange() {
    if (!GlobalBottomBar._focusNotifier.value && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onInputTextChanged);
    GlobalBottomBar._focusNotifier.removeListener(_onGlobalFocusChange);
    GlobalBottomBar._controllerInstance = null;
    GlobalBottomBar._submitCurrentInputCallback = null;
    GlobalBottomBar._requestFocusCallback = null;
    _inputScrollController.removeListener(_onInputScrollChanged);
    _inputScrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputTextChanged() {
    setState(() {});
    // Keep last line at bottom (20px from bar): scroll to end when in scroll mode so the typing line stays fixed.
    void scrollToBottom() {
      if (!mounted) return;
      if (_inputScrollController.hasClients) {
        final pos = _inputScrollController.position;
        if (pos.maxScrollExtent > 0) {
          _inputScrollController.jumpTo(pos.maxScrollExtent);
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToBottom();
      // Second frame so layout is fully updated (e.g. when crossing into scroll mode).
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToBottom());
    });
  }

  void _onInputScrollChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _navigateToNewPage() {
    String text = _controller.text.trim();
    if (text.isEmpty) {
      if (GlobalBottomBar.premadePromptOptions.isEmpty) return;
      final chosen = GlobalBottomBar.premadePromptOptions[
          math.Random().nextInt(GlobalBottomBar.premadePromptOptions.length)];
      _controller.text = chosen;
      _controller.selection = TextSelection.collapsed(offset: chosen.length);
      text = chosen;
      setState(() {});
    }

    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    if (!GlobalBottomBar.isAiPageOpen) {
      GlobalBottomBar.setAiPageOpen(true);
      navigator
          .push(MaterialPageRoute(builder: (_) => const AiPage()))
          .then((result) {
        // Run after frame so AI page dispose (backButton.hide()) has completed; then show Back on overlay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          GlobalBottomBar.setAiPageOpen(false);
          if (result == true) {
            GlobalBottomBar.requestInputFocus();
          }
        });
      });
    }

    _controller.clear();
    AiConversationController.instance.submitPrompt(text);
  }

  int _computeVisualLineCount({
    required String text,
    required TextStyle style,
    required double maxWidth,
  }) {
    if (maxWidth <= 0) return 1;
    final content = text.isEmpty ? ' ' : text;
    final painter = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics().length;
    return lines.clamp(1, 999);
  }

  @override
  Widget build(BuildContext context) {
    // 20px line height: height is multiplier of fontSize; even leading so no cumulative shift.
    final textStyle = TextStyle(
      fontFamily: 'Aeroport',
      fontSize: _fontSize,
      fontWeight: FontWeight.w500,
      height: _lineHeightPx / _fontSize,
      leadingDistribution: TextLeadingDistribution.even,
      color: AppTheme.textColor,
    );

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final constrainedWidth = outerConstraints.maxWidth > 600
              ? 600.0
              : outerConstraints.maxWidth;
          final inputWidth = (constrainedWidth - 15 - 15 - 5 - 15).clamp(80.0, 560.0);
          // Match TextField content width (decoration has right: 6) so line count matches and last line stays anchored.
          final textContentWidth = (inputWidth - 6).clamp(80.0, 560.0);
          final visualLines = _computeVisualLineCount(
            text: _controller.text,
            style: textStyle,
            maxWidth: textContentWidth,
          );
          // Bar extends for 1–7 lines (20px per line + 20 top + 20 bottom), then stays at 180px.
          final contentLines = visualLines.clamp(1, _maxLinesBeforeScroll);
          final computedHeight = _verticalPadding * 2 + _lineHeightPx * contentLines;
          _currentBarHeight = computedHeight;

          final isScrollMode = visualLines > _maxLinesBeforeScroll;
          final showInputScrollbar = isScrollMode &&
              _inputScrollController.hasClients &&
              _inputScrollController.position.maxScrollExtent > 0;

          final textField = TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: true,
            readOnly: false,
            showCursor: true,
            enableInteractiveSelection: true,
            cursorColor: AppTheme.textColor,
            cursorHeight: _fontSize,
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.send,
            scrollController: _inputScrollController,
            textAlignVertical: TextAlignVertical.bottom,
            style: textStyle,
            onSubmitted: (_) => _navigateToNewPage(),
            decoration: InputDecoration(
              hintText: (_isFocused || _controller.text.isNotEmpty)
                  ? null
                  : 'AI & Search',
              hintStyle: textStyle,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(left: 0, right: 6, top: 0, bottom: 0),
            ),
          );

          return Container(
            width: double.infinity,
            height: computedHeight,
            color: AppTheme.backgroundColor,
            child: Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 15, right: 15),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: _verticalPadding),
                                SizedBox(
                                  height: isScrollMode
                                      ? _scrollModeContentHeight
                                      : _lineHeightPx * contentLines,
                                  child: textField,
                                ),
                                const SizedBox(height: _verticalPadding),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Padding(
                            padding: const EdgeInsets.only(bottom: _applyIconBottomPadding),
                            child: GestureDetector(
                              onTap: () {
                                AppHaptic.heavy();
                                _navigateToNewPage();
                              },
                              child: SvgPicture.asset(
                                AppTheme.isLightTheme
                                    ? 'assets/icons/apply_light.svg'
                                    : 'assets/icons/apply_dark.svg',
                                width: 15,
                                height: 10,
                              ),
                            ).pointer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showInputScrollbar)
                  Positioned(
                    right: 5,
                    top: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final barHeight = constraints.maxHeight;
                        if (barHeight <= 0) {
                          return const SizedBox.shrink();
                        }
                        try {
                          final position = _inputScrollController.position;
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
                              (barHeight * indicatorHeightRatio)
                                  .clamp(0.0, barHeight);
                          if (indicatorHeight <= 0) {
                            return const SizedBox.shrink();
                          }
                          final scrollPosition =
                              (currentScroll / maxScroll).clamp(0.0, 1.0);
                          final availableSpace =
                              (barHeight - indicatorHeight)
                                  .clamp(0.0, barHeight);
                          final topPosition =
                              (scrollPosition * availableSpace)
                                  .clamp(0.0, barHeight);
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
            ),
          );
        },
      ),
    );
  }
}
