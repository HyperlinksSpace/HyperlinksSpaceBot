import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import '../app/theme/app_theme.dart';
import '../services/ai_chat_service.dart';
import '../telegram_safe_area.dart';
import '../utils/app_haptic.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/global/global_bottom_bar.dart';
import '../widgets/global/global_logo_bar.dart';

class AiConversationEntry {
  const AiConversationEntry({
    required this.prompt,
    required this.answer,
    required this.isLoading,
  });

  final String prompt;
  final String answer;
  final bool isLoading;

  AiConversationEntry copyWith({
    String? prompt,
    String? answer,
    bool? isLoading,
  }) {
    return AiConversationEntry(
      prompt: prompt ?? this.prompt,
      answer: answer ?? this.answer,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AiConversationController {
  AiConversationController._();

  static final AiConversationController instance = AiConversationController._();

  final ValueNotifier<List<AiConversationEntry>> entriesNotifier =
      ValueNotifier<List<AiConversationEntry>>(<AiConversationEntry>[]);

  final AiChatService _chatService = AiChatService();

  Future<void> submitPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;

    final current = List<AiConversationEntry>.from(entriesNotifier.value);
    final insertedIndex = current.length;
    current.add(
      const AiConversationEntry(
        prompt: '',
        answer: '',
        isLoading: true,
      ),
    );
    current[insertedIndex] = AiConversationEntry(
      prompt: trimmed,
      answer: '',
      isLoading: true,
    );
    entriesNotifier.value = current;

    try {
      final messages = _buildChatMessages(current, insertedIndex);
      final answer = await _chatService.ask(messages: messages);
      final updated = List<AiConversationEntry>.from(entriesNotifier.value);
      if (insertedIndex < updated.length) {
        updated[insertedIndex] = updated[insertedIndex].copyWith(
          answer: answer,
          isLoading: false,
        );
        entriesNotifier.value = updated;
      }
    } catch (e, st) {
      debugPrint('[AiConversation] submitPrompt failed: $e');
      debugPrint('$st');
      final updated = List<AiConversationEntry>.from(entriesNotifier.value);
      final errorText = kDebugMode
          ? 'Unable to get AI response right now. $e'
          : 'Unable to get AI response right now. Please try again.';
      if (insertedIndex < updated.length) {
        updated[insertedIndex] = updated[insertedIndex].copyWith(
          answer: errorText,
          isLoading: false,
        );
        entriesNotifier.value = updated;
      }
    }
  }

  List<Map<String, String>> _buildChatMessages(
    List<AiConversationEntry> entries,
    int latestIndex,
  ) {
    final messages = <Map<String, String>>[];
    for (var i = 0; i <= latestIndex; i++) {
      final item = entries[i];
      if (item.prompt.trim().isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': item.prompt.trim(),
        });
      }
      final answer = item.answer.trim();
      if (!item.isLoading && answer.isNotEmpty) {
        messages.add({
          'role': 'assistant',
          'content': answer,
        });
      }
    }
    return messages;
  }
}

class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _entryKeys = <int, GlobalKey>{};
  int _pinRetryCount = 0;
  double _latestEntryHeight = 0.0;
  // 30px design inset with 1px clip safety to prevent previous-edge bleed.
  static const double _latestEntryTopInset = 29.0;

  double _getAdaptiveBottomPadding() {
    final safeAreaInset = TelegramSafeAreaService().getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      // Pop with true so the bottom bar restores AI & Search widget opened state (focus + overlay)
      Navigator.of(context).pop(true);
    }
  }

  void _updateScrollIndicator() {
    if (_scrollController.hasClients) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicator);
    AiConversationController.instance.entriesNotifier
        .addListener(_onEntriesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinLatestEntryToTop();
      }
    });
    // Back button owned by AiSearchOverlay (centralized); no setup here
  }

  @override
  void dispose() {
    AiConversationController.instance.entriesNotifier
        .removeListener(_onEntriesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onEntriesChanged() {
    if (!mounted) return;
    final entries = AiConversationController.instance.entriesNotifier.value;
    for (var i = 0; i < entries.length; i++) {
      _entryKeys.putIfAbsent(i, GlobalKey.new);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinLatestEntryToTop();
      }
    });
  }

  Future<void> _pinLatestEntryToTop() async {
    if (!_scrollController.hasClients) return;
    final entries = AiConversationController.instance.entriesNotifier.value;
    if (entries.isEmpty) return;

    final latestIndex = entries.length - 1;
    final latestKey = _entryKeys.putIfAbsent(latestIndex, GlobalKey.new);
    var latestContext = latestKey.currentContext;

    // If latest item is not built yet, force-build and retry next frame.
    if (latestContext == null) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      latestContext = latestKey.currentContext;
      if (latestContext == null && _pinRetryCount < 3) {
        _pinRetryCount += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _pinLatestEntryToTop();
          }
        });
        return;
      }
    }
    if (latestContext == null) return;
    _pinRetryCount = 0;

    final latestRenderObject = latestContext.findRenderObject();
    if (latestRenderObject is! RenderBox) {
      return;
    }

    final latestHeight = latestRenderObject.size.height;
    if ((latestHeight - _latestEntryHeight).abs() > 0.5 && mounted) {
      setState(() {
        _latestEntryHeight = latestHeight;
      });
    }

    // Deterministic reveal math: get exact scroll offset for entry top.
    final viewport = RenderAbstractViewport.of(latestRenderObject);
    final revealTopOffset = viewport.getOffsetToReveal(latestRenderObject, 0.0).offset;
    final targetOffset =
        (revealTopOffset - _latestEntryTopInset).clamp(0.0, _scrollController.position.maxScrollExtent);

    if ((targetOffset - _scrollController.offset).abs() > 0.5) {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    // Match MainPage: small internal gap when not fullscreen.
    final needsScrollableTopGap = topPadding == 0.0;
    final bottomPadding = _getAdaptiveBottomPadding();
    final entries = AiConversationController.instance.entriesNotifier.value;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: topPadding,
                bottom: bottomPadding,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          15,
                          30 + (needsScrollableTopGap ? 10 : 0),
                          15,
                          30,
                        ),
                        itemCount: entries.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 30),
                        itemBuilder: (context, index) {
                          if (index == entries.length) {
                            // Only enough space so the latest entry can be pinned to top
                            // with no extra scrollable empty area below.
                            final spacerHeight = _latestEntryHeight > 0
                                ? (constraints.maxHeight -
                                        _latestEntryHeight -
                                        30.0)
                                    .clamp(0.0, double.infinity)
                                : 0.0;
                            return SizedBox(height: spacerHeight);
                          }
                          final entry = entries[index];
                          final itemKey =
                              _entryKeys.putIfAbsent(index, GlobalKey.new);
                          return Column(
                            key: itemKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.prompt,
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 30,
                                  height: 1.0,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.textColor,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                entry.isLoading ? 'Thinking...' : entry.answer,
                                style: TextStyle(
                                  fontFamily: 'Aeroport',
                                  fontSize: 15,
                                  height: 2.0,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textColor,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              right: 5,
              top: topPadding,
              bottom: bottomPadding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final containerHeight = constraints.maxHeight;
                  if (containerHeight <= 0 || !_scrollController.hasClients) {
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
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
