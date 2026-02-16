import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/theme/app_theme.dart';
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
}

class _GlobalBottomBarState extends State<GlobalBottomBar> {
  static bool _isAiPageOpen = false;
  static double _currentBarHeight = GlobalBottomBar.barHeight;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _inputScrollController = ScrollController();
  bool _isFocused = false;
  static const int _maxVisibleLines = 11;
  static const double _fontSize = 15.0;
  static const double _lineHeight = 1.0;
  static const double _verticalPadding = 22.0;

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
    _controller.addListener(() {
      setState(() {});
    });
    _inputScrollController.addListener(_onInputScrollChanged);
  }

  void _onGlobalFocusChange() {
    if (!GlobalBottomBar._focusNotifier.value && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
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

  void _onInputScrollChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _navigateToNewPage() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
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
    return lines.clamp(1, _maxVisibleLines);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontFamily: 'Aeroport',
      fontSize: _fontSize,
      fontWeight: FontWeight.w500,
      height: _lineHeight,
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
          final visualLines = _computeVisualLineCount(
            text: _controller.text,
            style: textStyle,
            maxWidth: inputWidth,
          );
          final computedHeight =
              (_verticalPadding * 2) + (visualLines * _fontSize * _lineHeight);
          _currentBarHeight = computedHeight;

          final showInputScrollbar = _inputScrollController.hasClients &&
              _inputScrollController.position.maxScrollExtent > 0;

          return Container(
            width: double.infinity,
            height: computedHeight,
            color: AppTheme.backgroundColor,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.only(left: 15, right: 15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: computedHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  enabled: true,
                                  readOnly: false,
                                  showCursor: true,
                                  enableInteractiveSelection: true,
                                  cursorColor: AppTheme.textColor,
                                  cursorHeight: _fontSize,
                                  maxLines: _maxVisibleLines,
                                  minLines: 1,
                                  textInputAction: TextInputAction.send,
                                  scrollController: _inputScrollController,
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
                                    contentPadding: const EdgeInsets.only(
                                      left: 0,
                                      right: 6,
                                      top: _verticalPadding,
                                      bottom: _verticalPadding,
                                    ),
                                  ),
                                ),
                              ),
                              if (showInputScrollbar)
                                Positioned(
                                  right: 0,
                                  top: _verticalPadding,
                                  bottom: _verticalPadding,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final containerHeight = constraints.maxHeight;
                                      if (containerHeight <= 0) {
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
                                        final ratio =
                                            (viewportHeight / totalHeight).clamp(0.0, 1.0);
                                        final indicatorHeight =
                                            (containerHeight * ratio).clamp(10.0, containerHeight);
                                        final availableSpace =
                                            (containerHeight - indicatorHeight).clamp(0.0, containerHeight);
                                        final scrollPosition =
                                            (currentScroll / maxScroll).clamp(0.0, 1.0);
                                        final top = (scrollPosition * availableSpace)
                                            .clamp(0.0, containerHeight);
                                        return Padding(
                                          padding: EdgeInsets.only(top: top),
                                          child: Container(
                                            width: 1,
                                            height: indicatorHeight,
                                            color: const Color(0xFF818181),
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
                        ),
                      ),
                      const SizedBox(width: 5),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 22),
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
    );
  }
}
