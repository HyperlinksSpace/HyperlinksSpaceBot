/**
 * Welcome-only header: black bar, wordmark (logo.svg art), About on the right.
 * Not used on other routes — see GlobalLogoBar.
 */
import React from "react";
import { View, Text, Pressable, StyleSheet, Linking } from "react-native";
import { useTelegram } from "./Telegram";
import { LogoWordmark } from "./LogoWordmark";
import { dark, light, useColors } from "../theme";

const LOGO_HEIGHT = 40;
const LOGO_WIDTH = (104 / 40) * LOGO_HEIGHT;
const VERTICAL_INDENT = 15;
const ABOUT_URL = "https://www.hyperlinks.space";

export function WelcomeMarketingHeader() {
  const { triggerHaptic } = useTelegram();
  const colors = useColors();
  const logoTextColor = colors.primary === light.primary ? dark.background : light.background;

  const onAbout = () => {
    triggerHaptic("light");
    void Linking.openURL(ABOUT_URL);
  };

  return (
    <View
      style={[
        styles.bar,
        {
          paddingTop: VERTICAL_INDENT,
          paddingBottom: VERTICAL_INDENT,
          backgroundColor: colors.background,
          borderBottomColor: colors.highlight,
        },
      ]}
    >
      <View style={styles.row}>
        <View style={styles.left} accessible accessibilityLabel="Hyperlinks Space">
          <LogoWordmark width={LOGO_WIDTH} height={LOGO_HEIGHT} textColor={logoTextColor} />
        </View>
        <Pressable
          onPress={onAbout}
          style={styles.aboutHit}
          accessibilityRole="link"
          accessibilityLabel="About"
          accessibilityHint="Opens hyperlinks.space in the browser"
        >
          <Text style={[styles.aboutText, { color: colors.primary }]}>About</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    width: "100%",
    alignSelf: "stretch",
    paddingHorizontal: 16,
    flexShrink: 0,
    borderBottomWidth: 1,
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    width: "100%",
  },
  left: {
    flexShrink: 1,
    marginRight: 12,
  },
  aboutHit: {
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  aboutText: {
    fontSize: 16,
    fontWeight: "400",
  },
});
