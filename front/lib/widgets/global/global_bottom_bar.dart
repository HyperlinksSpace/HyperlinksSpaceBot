import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/theme/app_theme.dart';
// TODO: AI functionality will be rebuilt from scratch
// import '../../pages/new_page.dart';
// import '../../analytics.dart';

// Global bottom bar widget that appears on all pages
class GlobalBottomBar extends StatefulWidget {
  const GlobalBottomBar({super.key});

  @override
  State<GlobalBottomBar> createState() => _GlobalBottomBarState();

  // Static notifier to track focus state across the app
  static final ValueNotifier<bool> _focusNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<bool> get focusNotifier => _focusNotifier;

  // Static method to unfocus the input (can be called from anywhere)
  static void unfocusInput() {
    _focusNotifier.value = false;
    // The actual unfocus will be handled by the state
  }

  // Static reference to the controller (set by the state)
  static TextEditingController? _controllerInstance;
  
  // Static method to set input text (can be called from anywhere)
  static void setInputText(String text) {
    if (_controllerInstance != null) {
      _controllerInstance!.text = text;
      _controllerInstance!.selection = TextSelection.collapsed(
        offset: text.length,
      );
    }
  }
}

class _GlobalBottomBarState extends State<GlobalBottomBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // Set the static controller reference
    GlobalBottomBar._controllerInstance = _controller;
    
    _focusNode.addListener(() {
      final newFocusState = _focusNode.hasFocus;
      setState(() {
        _isFocused = newFocusState;
      });
      // Update the global notifier
      GlobalBottomBar._focusNotifier.value = newFocusState;
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
      // Unfocus was requested globally
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    GlobalBottomBar._focusNotifier.removeListener(_onGlobalFocusChange);
    GlobalBottomBar._controllerInstance = null;
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _navigateToNewPage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      // TODO: AI functionality removed - will be rebuilt from scratch
      // For now, just clear the text field
      _controller.clear();
      
      // Optional: Show a placeholder message or snackbar
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('AI functionality coming soon...')),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        color: AppTheme.backgroundColor,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10, bottom: 15),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.only(left: 15, right: 15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 30),
                    child: _controller.text.isEmpty
                      ? SizedBox(
                          height: 30,
                          child: TextField(
                            key: _textFieldKey,
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: true,
                            readOnly: false,
                            cursorColor: AppTheme.textColor,
                            cursorHeight: 15,
                            maxLines: 11,
                            minLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 2.0,
                                color: AppTheme.textColor),
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
                                  height: 2.0),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: !_isFocused
                                  ? const EdgeInsets.only(
                                      left: 0,
                                      right: 0,
                                      top: 5,
                                      bottom: 5)
                                  : const EdgeInsets.only(right: 0),
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            key: _textFieldKey,
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: true,
                            readOnly: false,
                            cursorColor: AppTheme.textColor,
                            cursorHeight: 15,
                            maxLines: 11,
                            minLines: 1,
                            textAlignVertical: _controller.text
                                        .split('\n')
                                        .length ==
                                    1
                                ? TextAlignVertical.center
                                : TextAlignVertical.bottom,
                            style: TextStyle(
                                fontFamily: 'Aeroport',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 2,
                                color: AppTheme.textColor),
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
                                  height: 2),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: _controller.text
                                          .split('\n')
                                          .length >
                                      1
                                  ? const EdgeInsets.only(
                                      left: 0, right: 0, top: 11)
                                  : const EdgeInsets.only(right: 0),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 7.5),
                child: GestureDetector(
                  onTap: () {
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
          ),
        ),
      ),
    );
  }
}

