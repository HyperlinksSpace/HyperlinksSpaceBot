import { View, Text, useWindowDimensions, StyleSheet } from "react-native";
import { useColors } from "../../ui/theme";

const CONTENT_GAP_BELOW_HEADER = 10;
const HEADING_TO_SUBTITLE_GAP = 20;
const H_PADDING = 20;
const MAX_HEADING_WIDTH = 360;
const WIDE_LAYOUT_MIN_WIDTH = 400;

/**
 * Welcome screen: top header is rendered by GlobalLogoBar (marketing vs default by route + TMA mode).
 */
export default function WelcomeScreen() {
  const colors = useColors();
  const { width: windowWidth } = useWindowDimensions();

  const isWideLayout = windowWidth > WIDE_LAYOUT_MIN_WIDTH;
  const headingFontSize = isWideLayout ? 35 : 25;
  const headingLineHeight = isWideLayout ? 80 : 40;

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <View
        style={[
          styles.content,
          { paddingHorizontal: H_PADDING, paddingTop: CONTENT_GAP_BELOW_HEADER },
        ]}
      >
        <View style={styles.headingBlock}>
          <Text
            style={[
              styles.headingText,
              {
                color: colors.primary,
                fontSize: headingFontSize,
                lineHeight: headingLineHeight,
              },
            ]}
          >
            Welcome to our program
          </Text>
        </View>
        <View style={[styles.subtitleBlock, { marginTop: HEADING_TO_SUBTITLE_GAP }]}>
          <Text style={[styles.subtitleText, { color: colors.secondary }]}>
            This is the best way to earn and spend
          </Text>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  content: {
    alignItems: "center",
  },
  subtitleBlock: {
    width: "100%",
    maxWidth: MAX_HEADING_WIDTH,
  },
  subtitleText: {
    fontSize: 15,
    lineHeight: 30,
    fontWeight: "400",
    textAlign: "center",
    includeFontPadding: false,
    paddingVertical: 0,
  },
  headingBlock: {
    width: "100%",
    maxWidth: MAX_HEADING_WIDTH,
  },
  headingText: {
    fontWeight: "400",
    textAlign: "center",
    includeFontPadding: false,
    paddingVertical: 0,
    width: "100%",
  },
});
