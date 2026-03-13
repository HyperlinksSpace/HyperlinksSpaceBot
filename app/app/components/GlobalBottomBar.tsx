/**
 * Global AI & Search bar (bottom block).
 *
 * This mirrors the Flutter GlobalBottomBar behaviour:
 * - 20px line height, 20px top/bottom padding
 * - Bar grows from 1–7 lines, then caps at 180px and enables internal scroll
 * - Last line stays pinned 20px from the bottom while typing
 * - Apply icon is always 25px from the bottom
 */
import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  View,
  Text,
  TextInput,
  Pressable,
  StyleSheet,
  Keyboard,
  ScrollView,
  Platform,
  type NativeSyntheticEvent,
  type TextInputSubmitEditingEventData,
  type TextInputContentSizeChangeEventData,
  type TextInputScrollEventData,
  type NativeScrollEvent,
  type NativeSyntheticEvent as RnNativeEvent,
} from "react-native";
import { useRouter } from "expo-router";
import { useTelegram } from "./Telegram";
import Svg, { Path } from "react-native-svg";
import { colors, layout, icons } from "../theme";

const { maxContentWidth } = layout;
const {
  barMinHeight: BAR_MIN_HEIGHT,
  horizontalPadding: HORIZONTAL_PADDING,
  verticalPadding: VERTICAL_PADDING,
  applyIconBottom: APPLY_ICON_BOTTOM,
  lineHeight: LINE_HEIGHT,
  maxLinesBeforeScroll: MAX_LINES_BEFORE_SCROLL,
  maxBarHeight: MAX_BAR_HEIGHT,
} = layout.bottomBar;
const FONT_SIZE = 15;
// Scroll viewport height when the bar is at its maximum. Since we want the
// input box itself to fully occupy the bar vertically (no outer gap), this is
// equal to the max bar height.
const SCROLL_CONTENT_HEIGHT = MAX_BAR_HEIGHT;
const PREMADE_PROMPTS = [
  "What is the universe?",
  "Tell me about dogs token",
];

export function GlobalBottomBar() {
  const router = useRouter();
  const { triggerHaptic } = useTelegram();
  const [value, setValue] = useState("");
  const inputRef = useRef<TextInput>(null);
  const scrollRef = useRef<ScrollView>(null);
  // Baseline single-line height reported by the underlying textarea on web.
  const [baseContentHeight, setBaseContentHeight] = useState<number | null>(
    null,
  );
  const [contentHeight, setContentHeight] = useState<number>(LINE_HEIGHT);
  // Height of a hidden mirrored Text used for shrink (web) and grow (native when contentSize is unreliable).
  const [mirrorHeight, setMirrorHeight] = useState<number | null>(null);
  // Width of the input area so the mirror Text can wrap correctly on native (iOS/Android).
  const [inputAreaWidth, setInputAreaWidth] = useState<number | null>(null);
  const [scrollY, setScrollY] = useState(0);

  const isTelegramIOSWeb =
    Platform.OS === "web" &&
    typeof window !== "undefined" &&
    !!(window as any).Telegram?.WebApp &&
    (window as any).Telegram.WebApp.platform === "ios";

  // Web-only: wire up a native scroll listener on the underlying textarea
  // rendered by TextInput so we can track manual scroll that React Native Web
  // may not surface via onScroll.
  useEffect(() => {
    if (Platform.OS !== "web") return;
    if (typeof document === "undefined") return;

    const el = document.querySelector(
      '[data-ai-input="true"]',
    ) as HTMLElement | null;
    if (!el) return;

    const handleScroll = () => {
      const scrollTop = (el as HTMLTextAreaElement).scrollTop;
      if (typeof scrollTop !== "number") return;
      const contentH = (el as HTMLTextAreaElement).scrollHeight;
      const clientH = (el as HTMLTextAreaElement).clientHeight;
      const domRange = contentH - clientH;
      // Match native: viewport is SCROLL_CONTENT_HEIGHT (150), so scroll range is contentHeight - 150.
      const targetRange = contentH - SCROLL_CONTENT_HEIGHT;
      const effectiveY =
        domRange > 0 && targetRange > 0
          ? (scrollTop * targetRange) / domRange
          : scrollTop;
      setScrollY(effectiveY);
    };

    el.addEventListener("scroll", handleScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", handleScroll);
    };
  }, []);

  const submit = useCallback(() => {
    triggerHaptic("heavy");
    let text = value.trim();
    if (!text && PREMADE_PROMPTS.length > 0) {
      text =
        PREMADE_PROMPTS[
          Math.floor(Math.random() * PREMADE_PROMPTS.length)
        ] ?? "";
      setValue(text);
    }
    if (!text) return;
    Keyboard.dismiss();
    setValue("");
    router.push({ pathname: "/ai" as any, params: { prompt: text } });
  }, [value, router, triggerHaptic]);

  const onSubmitEditing = useCallback(
    (_e: NativeSyntheticEvent<TextInputSubmitEditingEventData>) => {
      submit();
    },
    [submit]
  );

  const onContentSizeChange = useCallback(
    (e: NativeSyntheticEvent<TextInputContentSizeChangeEventData>) => {
      const h = e.nativeEvent.contentSize.height;
      if (!Number.isFinite(h)) return;
      setBaseContentHeight((prev) => (prev == null ? h : prev));
      setContentHeight(h);
      // Compute how many lines this content represents.
      const lines = Math.max(1, Math.ceil(h / LINE_HEIGHT));
      // For 1–7 lines we rely purely on bottom alignment and growing viewport.
      // Starting from the 9th line we auto-scroll so older lines move under the
      // top edge while the last line stays at the arrow baseline.
      if (lines > MAX_LINES_BEFORE_SCROLL + 1) {
        setTimeout(() => {
          if (scrollRef.current) {
            // Scroll so that the bottom of the content sits exactly at the
            // bottom of the viewport (SCROLL_CONTENT_HEIGHT). This keeps the
            // last line aligned with the arrow without clipping it.
            const targetY = Math.max(0, h - SCROLL_CONTENT_HEIGHT);
            scrollRef.current.scrollTo({ y: targetY, animated: false });
          }
        }, 0);
      }
    },
    []
  );

  const onChangeText = useCallback((text: string) => {
    setValue(text);
  }, []);

  const onScroll = useCallback(
    (e: RnNativeEvent<NativeScrollEvent>) => {
      const y = e.nativeEvent.contentOffset.y;
      // Debug helper (disabled by default):
      // console.log("[GlobalBottomBar] outer scrollY:", y);
      setScrollY(y);
    },
    []
  );

  const onInputScroll = useCallback(
    (e: NativeSyntheticEvent<TextInputScrollEventData>) => {
      // On some platforms (notably web), TextInput's scroll event may not
      // include a contentOffset; guard against that shape before reading.
      const offset = (e.nativeEvent as any)?.contentOffset;
      if (!offset || typeof offset.y !== "number") return;
      // Debug helper (disabled by default):
      // console.log("[GlobalBottomBar] input scrollY:", offset.y);
      setScrollY(offset.y);
    },
    [],
  );

  // Growth logic: derive line count from measured TextInput content height.
  const heightBasedLines = React.useMemo(() => {
    if (baseContentHeight == null) return 1;
    return Math.max(
      1,
      Math.min(
        999,
        1 +
          Math.floor(
            Math.max(
              0,
              (contentHeight - baseContentHeight + LINE_HEIGHT * 0.25) /
                LINE_HEIGHT,
            ),
          ),
      ),
    );
  }, [baseContentHeight, contentHeight]);

  // Shrink guard / native driver: we use a hidden mirrored Text with identical
  // typography (and on native, explicit width from inputAreaWidth) to measure how
  // many visual lines the current value occupies.
  const shrinkGuardLines = React.useMemo(() => {
    if (mirrorHeight == null) return 999;
    const approxLines = Math.max(1, Math.round(mirrorHeight / LINE_HEIGHT));
    return Math.max(1, Math.min(999, approxLines));
  }, [mirrorHeight]);

  // Final visual line count:
  // - Web: min(heightBasedLines, shrinkGuardLines) so we grow from content size and shrink from mirror.
  // - Native: mirror drives both grow and shrink (onContentSizeChange is unreliable on iOS); fallback to heightBasedLines when mirror not yet measured.
  const visualLines =
    Platform.OS === "web"
      ? Math.min(heightBasedLines, shrinkGuardLines)
      : (mirrorHeight != null ? shrinkGuardLines : heightBasedLines);

  // Intrinsic TextInput box height based purely on line count, capped at 8
  // lines (8 * 20 = 160px).
  const intrinsicHeight = Math.min(
    (MAX_LINES_BEFORE_SCROLL + 1) * LINE_HEIGHT,
    visualLines * LINE_HEIGHT,
  );
  // Final dynamic height:
  // - Minimum 60px (3 lines) so the bar never shrinks below 60.
  // - Maximum 180px: above that the bar stops growing and we switch to scrolling.
  const dynamicHeight = Math.max(
    60,
    Math.min(MAX_BAR_HEIGHT, intrinsicHeight),
  );
  const inputDynamicStyle = {
    minHeight: dynamicHeight,
    height: dynamicHeight,
    maxHeight: dynamicHeight,
  };

  // Bar height directly matches the input height, clamped between 60 and 180.
  const barHeight = dynamicHeight;
  // Viewport height:
  // - When bar < max (<= 180): viewport is the same as the input height.
  // - Once we reach the max (180): viewport fixed at 180 while content can grow.
  const inputContainerHeight =
    barHeight < MAX_BAR_HEIGHT ? barHeight : SCROLL_CONTENT_HEIGHT;
  // Scroll mode (custom scrollbar + auto-scroll) once the bar has reached its
  // maximum height and the content is taller than the viewport.
  const isScrollMode = barHeight >= MAX_BAR_HEIGHT && contentHeight > inputContainerHeight;

  // Scrollbar maths: mirror Flutter implementation.
  // barHeight: total bar height; viewportHeight: scroll viewport for text.
  const viewportHeight = inputContainerHeight;
  // Use the intrinsic content height reported by the TextInput to determine
  // how much text exists in total. The viewport still corresponds to the
  // outer ScrollView height (viewportHeight), so the indicator height is the
  // fraction of total text that is currently visible:
  //   indicatorHeightRatio = viewportHeight / scrollContentHeight.
  const scrollContentHeight = contentHeight;
  const showScrollbar = isScrollMode && scrollContentHeight > viewportHeight;
  // Scroll range for the outer ScrollView is based on the intrinsic content
  // height vs. the viewport height.
  const scrollRange = Math.max(scrollContentHeight - viewportHeight, 0);
  let indicatorHeight = 0;
  let topPosition = 0;
  if (showScrollbar && scrollRange > 0 && scrollContentHeight > 0) {
    const indicatorHeightRatio = Math.min(
      1,
      Math.max(0, viewportHeight / scrollContentHeight),
    );
    indicatorHeight = Math.min(
      barHeight,
      Math.max(0, barHeight * indicatorHeightRatio),
    );
    const scrollPosition = Math.min(1, Math.max(0, scrollY / scrollRange));
    const availableSpace = Math.min(
      barHeight,
      Math.max(0, barHeight - indicatorHeight),
    );
    // Here scrollY/scrollRange (scrollPosition) is 0 when the top of the text
    // is visible and 1 when the bottom is fully visible. We want the indicator
    // to be at the top of the bar when at the very top of the content, and at
    // the bottom of the bar when scrolled to the bottom, so we map
    // 0 → top, 1 → bottom directly.
    topPosition = Math.min(
      barHeight,
      Math.max(0, scrollPosition * availableSpace),
    );
  }

  return (
    <View style={[styles.wrapper, { height: barHeight }]}>
      <View style={[styles.container, { height: barHeight }]}>
        <View style={styles.inner}>
          <View style={styles.row}>
          <View style={{ flex: 1 }}>
            <View
              style={{
                height: inputContainerHeight,
                justifyContent: "flex-start",
              }}
            >
              <ScrollView
                ref={scrollRef}
                style={{ flex: 1 }}
                contentContainerStyle={{
                  paddingRight: 6,
                  flexGrow: 1,
                  justifyContent: "flex-end",
                }}
                onScroll={onScroll}
                scrollEventThrottle={16}
                showsVerticalScrollIndicator={false}
              >
                <View
                  style={{
                    flexGrow: 1,
                    justifyContent: "flex-end",
                    position: "relative", // for right-side overlay / gutter
                  }}
                  onLayout={
                    Platform.OS !== "web"
                      ? (e) => {
                          const w = e.nativeEvent.layout.width;
                          if (Number.isFinite(w) && w > 0) setInputAreaWidth(w);
                        }
                      : undefined
                  }
                >
                  <TextInput
                    ref={inputRef}
                    style={[styles.input, styles.inputWeb, inputDynamicStyle]}
                    placeholder="AI & Search"
                    placeholderTextColor="#818181"
                    value={value}
                    onChangeText={onChangeText}
                    onSubmitEditing={onSubmitEditing}
                    returnKeyType="send"
                    blurOnSubmit={false}
                    multiline
                    maxLength={4096}
                    onContentSizeChange={onContentSizeChange}
                    scrollEnabled
                    onScroll={onInputScroll}
                    // @ts-expect-error dataSet is a valid prop on web (used for CSS targeting)
                    dataSet={{ "ai-input": "true" }}
                  />
                  {Platform.OS === "web" && (
                    <View
                      pointerEvents="none"
                      style={{
                        position: "absolute",
                        top: 0,
                        bottom: 0,
                        right: 0,
                        // Wider gutter on Telegram iOS webview so the
                        // native blue scroll thumb (if drawn) sits well
                        // away from the caret and last characters.
                        width: isTelegramIOSWeb ? 24 : 12,
                        backgroundColor: colors.background,
                      }}
                    />
                  )}
                  <Text
                    style={[
                      styles.input,
                      styles.inputWeb,
                      {
                        position: "absolute",
                        opacity: 0,
                        pointerEvents: "none",
                        left: 0,
                        right: 0,
                        // On native, give mirror explicit width so it wraps like the input and reports correct height.
                        ...(Platform.OS !== "web" &&
                          inputAreaWidth != null && { width: inputAreaWidth }),
                      },
                    ]}
                    numberOfLines={0}
                    onLayout={(e) => {
                      const h = e.nativeEvent.layout.height;
                      if (Number.isFinite(h) && h > 0) {
                        setMirrorHeight(h);
                      }
                    }}
                  >
                    {value || " "}
                  </Text>
                </View>
              </ScrollView>
            </View>
          </View>
          <Pressable
            style={styles.applyWrap}
            onPress={submit}
            accessibilityRole="button"
            accessibilityLabel="Send"
          >
            <Svg
              width={icons.apply.width}
              height={icons.apply.height}
              viewBox="0 0 15 10"
            >
              <Path
                d="M1 5H10M6 1L10 5L6 9"
                stroke={colors.text}
                strokeWidth={1.5}
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </Svg>
          </Pressable>
        </View>
      </View>
      </View>
      {showScrollbar && indicatorHeight > 0 && (
        <View style={[styles.scrollbarContainer, { height: barHeight }]}>
          <View
            style={[
              styles.scrollbarIndicator,
              { height: indicatorHeight, marginTop: topPosition },
            ]}
          />
        </View>
      )}
    </View>
  );
}

const SCROLLBAR_INSET = 5;

const styles = StyleSheet.create({
  wrapper: {
    width: "100%",
    position: "relative",
  },
  container: {
    width: "100%",
    maxWidth: maxContentWidth,
    alignSelf: "center",
    backgroundColor: colors.background,
    // Remove vertical gap outside the input; the input box itself occupies the
    // full bar height.
    paddingVertical: 0,
    paddingHorizontal: HORIZONTAL_PADDING,
  },
  inner: {
    width: "100%",
  },
  row: {
    flexDirection: "row",
    alignItems: "flex-end",
    gap: 5,
  },
  input: {
    flex: 1,
    fontSize: FONT_SIZE,
    color: colors.text,
    // Target 20px visual line height; the outer container + ScrollView
    // control how much vertical space is available, so we don't fix the
    // TextInput height explicitly.
    lineHeight: LINE_HEIGHT,
    paddingVertical: 0,
    paddingHorizontal: 0,
    borderWidth: 0,
    borderColor: "transparent",
    backgroundColor: "transparent",
  },
  // Baseline overrides: relax RN Web default minHeight (40) and rely on our
  // dynamic height logic (inputDynamicStyle) instead.
  inputWeb: {
    minHeight: 0,
    // Base gutter so the caret and last characters never sit directly in the
    // system scrollbar lane. On Telegram iOS we add extra right padding at
    // runtime via the overlay width (see isTelegramIOSWeb logic).
    paddingRight: 12,
  },
  applyWrap: {
    // 25px padding from the bottom edge of the bar.
    paddingBottom: 25,
    justifyContent: "center",
    alignItems: "center",
  },
  applyIcon: {
    width: 15,
    height: 10,
    backgroundColor: "#1a1a1a",
    borderRadius: 1,
  },
  scrollbarContainer: {
    position: "absolute",
    right: SCROLLBAR_INSET,
    top: 0,
    alignItems: "flex-start",
    justifyContent: "flex-start",
  },
  scrollbarIndicator: {
    width: 1,
    backgroundColor: colors.scrollbar,
  },
});
