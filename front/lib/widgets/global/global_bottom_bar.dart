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
  static void setAiPageOpen(bool isOpen) {
    _GlobalBottomBarState._isAiPageOpen = isOpen;
  }

  // Static method to unfocus the input (can be called from anywhere)
  static void unfocusInput() {
    _focusNotifier.value = false;
    // The actual unfocus will be handled by the state
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
    return barHeight;
  }
}

class _GlobalBottomBarState extends State<GlobalBottomBar> {
  static bool _isAiPageOpen = false;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // Set the static controller reference
    GlobalBottomBar._controllerInstance = _controller;
    GlobalBottomBar._submitCurrentInputCallback = _navigateToNewPage;

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
      if (_controller.text.contains('\n')) {
        final textWithoutNewline = _controller.text.replaceAll('\n', '');
        _controller.value = TextEditingValue(
          text: textWithoutNewline,
          selection: TextSelection.collapsed(offset: textWithoutNewline.length),
        );
      }
      setState(() {});
    });
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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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
          .then((_) => GlobalBottomBar.setAiPageOpen(false));
    }

    _controller.clear();
    AiConversationController.instance.submitPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    // Bar: fixed height (22 top + 15 line + 22 bottom), fully undercovered by background.
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: GlobalBottomBar.barHeight,
        color: AppTheme.backgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: GlobalBottomBar.barHeight,
                      child: Center(
                        child: _controller.text.isEmpty
                            ? TextField(
                                key: _textFieldKey,
                                controller: _controller,
                                focusNode: _focusNode,
                                enabled: true,
                                readOnly: false,
                                showCursor: true,
                                enableInteractiveSelection: true,
                                cursorColor: AppTheme.textColor,
                                cursorHeight: 15,
                                maxLines: 11,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                textAlignVertical: TextAlignVertical.center,
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                  color: AppTheme.textColor,
                                ),
                                onSubmitted: (value) {
                                  _navigateToNewPage();
                                },
                                onChanged: (value) {},
                                decoration: InputDecoration(
                                  hintText: (_isFocused ||
                                          _controller.text.isNotEmpty)
                                      ? null
                                      : 'AI & Search',
                                  hintStyle: TextStyle(
                                    color: AppTheme.textColor,
                                    fontFamily: 'Aeroport',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.0,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.only(
                                    left: 0,
                                    right: 0,
                                    top: 22,
                                    bottom: 22,
                                  ),
                                ),
                              )
                            : TextField(
                                key: _textFieldKey,
                                controller: _controller,
                                focusNode: _focusNode,
                                enabled: true,
                                readOnly: false,
                                showCursor: true,
                                enableInteractiveSelection: true,
                                cursorColor: AppTheme.textColor,
                                cursorHeight: 15,
                                maxLines: 1,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                textAlignVertical:
                                    _controller.text.split('\n').length == 1
                                        ? TextAlignVertical.center
                                        : TextAlignVertical.bottom,
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                  color: AppTheme.textColor,
                                ),
                                onSubmitted: (value) {
                                  _navigateToNewPage();
                                },
                                onChanged: (value) {},
                                decoration: InputDecoration(
                                  hintText: (_isFocused ||
                                          _controller.text.isNotEmpty)
                                      ? null
                                      : 'AI & Search',
                                  hintStyle: TextStyle(
                                    color: AppTheme.textColor,
                                    fontFamily: 'Aeroport',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.0,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      _controller.text.split('\n').length > 1
                                          ? const EdgeInsets.only(
                                              left: 0,
                                              right: 0,
                                              top: 22,
                                              bottom: 22)
                                          : const EdgeInsets.only(
                                              left: 0,
                                              right: 0,
                                              top: 22,
                                              bottom: 22,
                                            ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  GestureDetector(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
