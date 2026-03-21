import "../global.css";
import { View, StyleSheet, Platform, KeyboardAvoidingView } from "react-native";
import { Stack } from "expo-router";
import { TelegramProvider } from "./components/Telegram";
import { GlobalLogoBarWithFallback } from "./components/GlobalLogoBarWithFallback";
import { GlobalBottomBar } from "./components/GlobalBottomBar";
import { GlobalBottomBarWeb } from "./components/GlobalBottomBarWeb";
import { useColors } from "./theme";
import { useTelegram } from "./components/Telegram";

/**
 * Three-block column layout (same as Flutter):
 * 1. Logo bar (optional in TMA when not fullscreen)
 * 2. Main area (flex, scrollable per screen) – Stack updates on route change
 * 3. [Web only] Raw HTML textarea test (compare with GlobalBottomBar in TMA)
 * 4. AI & Search bar (fixed at bottom)
 */
export default function RootLayout() {
  return (
    <TelegramProvider>
      {Platform.OS === "ios" ? (
        <KeyboardAvoidingView
          style={styles.keyboardAvoid}
          behavior="padding"
          keyboardVerticalOffset={0}
        >
          <RootContent />
        </KeyboardAvoidingView>
      ) : (
        <RootContent />
      )}
    </TelegramProvider>
  );
}

function RootContent() {
  const colors = useColors();
  const { themeBgReady, useTelegramTheme } = useTelegram();
  const backgroundColor = themeBgReady ? colors.background : "transparent";
  // Stronger than opacity:0 — avoids one frame of dark RN-web compositing before themeBgReady.
  const hideWebUntilTheme =
    Platform.OS === "web" && useTelegramTheme && !themeBgReady;

  return (
    <View
      style={[
        styles.root,
        {
          backgroundColor,
          opacity: themeBgReady ? 1 : 0,
          pointerEvents: themeBgReady ? "auto" : "none",
          ...(Platform.OS === "web"
            ? { display: hideWebUntilTheme ? "none" : "flex" }
            : {}),
        },
      ]}
    >
      <GlobalLogoBarWithFallback />
      <View style={styles.main}>
        <Stack screenOptions={{ headerShown: false }} />
      </View>
      {Platform.OS === "web" ? (
        // Avoid mounting textarea/DOM mirror before theme — kills dark flash from RN-web inputs.
        !useTelegramTheme || themeBgReady ? (
          <GlobalBottomBarWeb />
        ) : null
      ) : (
        <GlobalBottomBar />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  keyboardAvoid: {
    flex: 1,
  },
  root: {
    flex: 1,
    flexDirection: "column",
    overflow: "hidden",
  },
  main: {
    flex: 1,
    minHeight: 0,
  },
});
